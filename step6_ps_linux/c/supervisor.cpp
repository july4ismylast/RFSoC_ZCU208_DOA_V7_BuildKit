// supervisor.cpp -- the Cortex-A53 side: cells in, tracks and telemetry out.
//
// This is the Linux half of the PS.  It is deliberately small and dependency
// free (C++17, the standard library only) because it has to run on a PetaLinux
// root filesystem where nothing else is installed:
//
//     cells (JSONL on stdin)  ->  ladder + track store  ->  telemetry (JSONL)
//
// It carries the same four rungs as step5_r5_tracking/py/ladder.py:
//
//     modulation -> direction -> bandwidth -> cadence
//
// and the same gates (see ladder.py).  The duplication is intentional and
// bounded: the A53 does not link the RPU's bare-metal code, and a 200-line file
// twice is cheaper than a shared library across two cores with different ABIs.
// If you change a gate here, change it there, and run
//
//     python3 step6_ps_linux/testbench/run_testbench.py
//
// which feeds the same fixture to both and compares the track counts.
//
//   usage: supervisor [--policy full|direction-only] [--retire N] [--quiet]
//
// input  one JSON object per line, keys: frame, az, el, bw_hz, mod [, verified]
// output one JSON object per line: frame, track, az, el, bw_hz, mod, state
//        state is born, update or retired
// summary on stderr: frames, cells, tracks, born, retired, retired_ghosts
//
// Build:  make            (host, for the test bench)
//         make cross      (aarch64, for the board; needs the cross toolchain)

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <algorithm>
#include <cstring>
#include <map>
#include <string>
#include <vector>

namespace {

struct Cell {
    int frame = 0;
    double az = 0.0;
    double el = 0.0;
    double bw = 0.0;
    std::string mod;
    bool verified = false;
};

struct Track {
    int id = 0;
    int last_frame = 0;
    int cells = 0;
    double az = 0.0;
    double el = 0.0;
    double bw = 0.0;
    std::string mod;
    std::map<std::string, int> votes;
    bool verified = false;
};

struct Policy {
    bool use_modulation = true;
    int retire_after = 3;
    double sigma_direction = 0.5;   // degrees
    double sigma_bandwidth = 0.35;  // log ratio
    double sigma_cadence = 1.5;     // frames
    double gate_direction = 1.5;
    double gate_bandwidth = 1.0;
    double gate_cadence = 1.2;
    double mod_penalty = 9.0;
};

// ---------------------------------------------------------------------------
// a JSON reader for one flat object.  Numbers and quoted strings only, which is
// exactly the schema above; anything else is a malformed line and is counted.
// ---------------------------------------------------------------------------
bool read_double(const std::string &line, const char *key, double *out)
{
    std::string needle = std::string("\"") + key + "\"";
    std::size_t at = line.find(needle);
    if (at == std::string::npos) {
        return false;
    }
    at = line.find(':', at + needle.size());
    if (at == std::string::npos) {
        return false;
    }
    *out = std::strtod(line.c_str() + at + 1, nullptr);
    return true;
}

bool read_string(const std::string &line, const char *key, std::string *out)
{
    std::string needle = std::string("\"") + key + "\"";
    std::size_t at = line.find(needle);
    if (at == std::string::npos) {
        return false;
    }
    at = line.find(':', at + needle.size());
    std::size_t quote = line.find('"', at + 1);
    if (at == std::string::npos || quote == std::string::npos) {
        return false;
    }
    std::size_t end = line.find('"', quote + 1);
    if (end == std::string::npos) {
        return false;
    }
    *out = line.substr(quote + 1, end - quote - 1);
    return true;
}

bool parse_cell(const std::string &line, Cell *cell)
{
    double value = 0.0;
    if (!read_double(line, "frame", &value)) {
        return false;
    }
    cell->frame = static_cast<int>(value);
    if (!read_double(line, "az", &cell->az) || !read_double(line, "el", &cell->el)) {
        return false;
    }
    if (!read_double(line, "bw_hz", &cell->bw) || !read_string(line, "mod", &cell->mod)) {
        return false;
    }
    if (read_double(line, "verified", &value)) {
        cell->verified = value != 0.0;
    }
    return true;
}

struct Residuals {
    double modulation = 0.0;
    double direction = 0.0;
    double bandwidth = 0.0;
    double cadence = 0.0;
    bool have_direction = false;
    bool have_bandwidth = false;
    bool have_cadence = false;
};

Residuals residuals_of(const Cell &cell, const Track &track, const Policy &policy)
{
    Residuals out;
    out.modulation = (cell.mod == track.mod) ? 0.0 : policy.mod_penalty;
    if (track.cells > 0) {
        out.direction = std::hypot(cell.az - track.az, cell.el - track.el)
                        / policy.sigma_direction;
        out.have_direction = true;
        out.bandwidth = std::fabs(std::log(std::max(cell.bw, 1e6) / std::max(track.bw, 1e6)))
                        / policy.sigma_bandwidth;
        out.have_bandwidth = true;
        int gap = cell.frame - track.last_frame;
        out.cadence = static_cast<double>(std::max(0, gap - 1)) / policy.sigma_cadence;
        out.have_cadence = true;
    }
    return out;
}

bool passes(const Cell &cell, const Track &track, const Policy &policy, double *cost)
{
    Residuals r = residuals_of(cell, track, policy);
    if (policy.use_modulation && r.modulation > 0.5) {
        return false;
    }
    if (r.have_direction && r.direction > policy.gate_direction) {
        return false;
    }
    if (r.have_bandwidth && r.bandwidth > policy.gate_bandwidth) {
        return false;
    }
    if (r.have_cadence && r.cadence > policy.gate_cadence) {
        return false;
    }
    *cost = r.modulation * r.modulation
            + (r.have_direction ? r.direction * r.direction : 0.0)
            + (r.have_bandwidth ? r.bandwidth * r.bandwidth : 0.0)
            + (r.have_cadence ? r.cadence * r.cadence : 0.0);
    return true;
}

void absorb(Track *track, const Cell &cell)
{
    track->cells += 1;
    track->last_frame = cell.frame;
    double weight = 1.0 / track->cells;
    track->az += (cell.az - track->az) * weight;
    track->el += (cell.el - track->el) * weight;
    track->bw = (track->cells == 1) ? cell.bw : track->bw + (cell.bw - track->bw) * weight;
    track->votes[cell.mod] += 1;
    int best = -1;
    for (const auto &pair : track->votes) {
        if (pair.second > best) {
            best = pair.second;
            track->mod = pair.first;
        }
    }
    track->verified = track->verified || cell.verified;
}

}  // namespace

int main(int argc, char **argv)
{
    Policy policy;
    bool quiet = false;
    for (int index = 1; index < argc; ++index) {
        if (std::strcmp(argv[index], "--quiet") == 0) {
            quiet = true;
        } else if (std::strcmp(argv[index], "--policy") == 0 && index + 1 < argc) {
            policy.use_modulation = std::strcmp(argv[++index], "direction-only") != 0;
        } else if (std::strcmp(argv[index], "--retire") == 0 && index + 1 < argc) {
            policy.retire_after = std::atoi(argv[++index]);
        } else if (std::strcmp(argv[index], "--help") == 0) {
            std::printf("usage: supervisor [--policy full|direction-only] [--retire N]\n");
            return 0;
        }
    }

    std::vector<Track> tracks;
    int next_id = 1;
    int current_frame = 0;
    long cells = 0;
    long malformed = 0;
    long born = 0;
    long retired = 0;
    long ghost_retired = 0;
    int live_at_start = 0;

    char buffer[4096];
    while (std::fgets(buffer, sizeof(buffer), stdin) != nullptr) {
        std::string line(buffer);
        if (line.find_first_not_of(" \t\r\n") == std::string::npos) {
            continue;
        }
        Cell cell;
        if (!parse_cell(line, &cell)) {
            malformed += 1;
            continue;
        }
        cells += 1;
        current_frame = std::max(current_frame, cell.frame);
        live_at_start = static_cast<int>(tracks.size());

        // greedy: cheapest passing pair first, exactly like ladder.associate()
        std::vector<std::pair<double, std::pair<int, int>>> candidates;
        for (std::size_t index = 0; index < tracks.size(); ++index) {
            double cost = 0.0;
            if (passes(cell, tracks[index], policy, &cost)) {
                candidates.emplace_back(cost, std::make_pair(0, static_cast<int>(index)));
            }
        }
        std::sort(candidates.begin(), candidates.end());
        int chosen = -1;
        if (!candidates.empty()) {
            chosen = candidates.front().second.second;
        }
        if (chosen >= 0) {
            absorb(&tracks[static_cast<std::size_t>(chosen)], cell);
        } else {
            Track fresh;
            fresh.id = next_id++;
            fresh.last_frame = cell.frame;
            fresh.bw = cell.bw;
            fresh.mod = cell.mod;
            fresh.cells = 0;
            absorb(&fresh, cell);
            tracks.push_back(fresh);
            chosen = static_cast<int>(tracks.size()) - 1;
            born += 1;
        }
        if (!quiet) {
            const Track &track = tracks[static_cast<std::size_t>(chosen)];
            std::printf("{\"frame\":%d,\"track\":%d,\"az\":%.4f,\"el\":%.4f,"
                        "\"bw_hz\":%.3f,\"mod\":\"%s\",\"state\":\"%s\","
                        "\"verified\":%s}\n",
                        cell.frame, track.id, track.az, track.el, track.bw,
                        track.mod.c_str(), track.cells == 1 ? "born" : "update",
                        track.verified ? "true" : "false");
        }

        // retire ghosts: a track whose last cell is older than retire_after
        for (auto iterator = tracks.begin(); iterator != tracks.end();) {
            if (current_frame - iterator->last_frame > policy.retire_after) {
                if (!quiet) {
                    std::printf("{\"frame\":%d,\"track\":%d,\"az\":%.4f,\"el\":%.4f,"
                                "\"bw_hz\":%.3f,\"mod\":\"%s\",\"state\":\"retired\","
                                "\"verified\":%s}\n",
                                current_frame, iterator->id, iterator->az, iterator->el,
                                iterator->bw, iterator->mod.c_str(),
                                iterator->verified ? "true" : "false");
                }
                retired += 1;
                if (iterator->last_frame != cell.frame) {
                    ghost_retired += 1;
                }
                iterator = tracks.erase(iterator);
            } else {
                ++iterator;
            }
        }
    }

    std::fprintf(stderr,
                 "supervisor: frames=%d cells=%ld tracks_live=%zu born=%ld retired=%ld "
                 "ghosts=%ld malformed=%ld policy=%s\n",
                 current_frame + 1, cells, tracks.size(), born, retired, ghost_retired,
                 malformed, policy.use_modulation ? "full" : "direction-only");
    return malformed == cells ? 1 : 0;
}
