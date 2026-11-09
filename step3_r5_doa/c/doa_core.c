/* doa_core.c -- see doa_core.h.  Plain C99, libm only. */

#include "doa_core.h"

#include <math.h>

#define C_LIGHT 299792458.0
#define PI 3.14159265358979323846
#define DEG (180.0 / PI)
#define RAD (PI / 180.0)

static const int PAIRS[6][2] = {{0, 1}, {0, 2}, {0, 3}, {1, 2}, {1, 3}, {2, 3}};

/* element positions in the y-z plane */
static void positions(double dy_m, double dz_m, double p[4][2])
{
    p[0][0] = -dy_m / 2.0; p[0][1] = -dz_m / 2.0;
    p[1][0] = +dy_m / 2.0; p[1][1] = -dz_m / 2.0;
    p[2][0] = -dy_m / 2.0; p[2][1] = +dz_m / 2.0;
    p[3][0] = +dy_m / 2.0; p[3][1] = +dz_m / 2.0;
}

static void direction(double az_deg, double el_deg, double u[3])
{
    double az = az_deg * RAD, el = el_deg * RAD;
    u[0] = cos(el) * cos(az);
    u[1] = cos(el) * sin(az);
    u[2] = sin(el);
}

/* (uy, uz) -> degrees, the same convention the MATLAB reference uses:
 *   el = asin(uz)              (not atan2(uz, ux): WPI can return |u| < 1)
 *   az = atan2(uy, sqrt(1 - uy^2 - uz^2))
 */
static void angles(double uy, double uz, double *az_deg, double *el_deg)
{
    double ux2 = 1.0 - uy * uy - uz * uz;
    double ux = (ux2 > 0.0) ? sqrt(ux2) : 0.0;
    double clamped = uz;
    if (clamped > 1.0) {
        clamped = 1.0;
    }
    if (clamped < -1.0) {
        clamped = -1.0;
    }
    *el_deg = asin(clamped) * DEG;
    *az_deg = atan2(uy, ux) * DEG;
    if (ux <= 1e-12) {
        *az_deg = (uy >= 0.0) ? 90.0 : -90.0;
    }
}

/* a[n] = exp(-j*k*(p_n . u)) */
static void steering(const double p[4][2], double wave_number, const double u[3],
                     double a_re[4], double a_im[4])
{
    int n;
    for (n = 0; n < 4; ++n) {
        double phase = -wave_number * (p[n][0] * u[1] + p[n][1] * u[2]);
        a_re[n] = cos(phase);
        a_im[n] = sin(phase);
    }
}

double doa_bartlett(const double *r_re, const double *r_im, double fc_hz,
                    double dy_m, double dz_m, double az_deg, double el_deg)
{
    double p[4][2], u[3], a_re[4], a_im[4];
    double wave_number = 2.0 * PI * fc_hz / C_LIGHT;
    double total = 0.0;
    int row, column;
    positions(dy_m, dz_m, p);
    direction(az_deg, el_deg, u);
    steering(p, wave_number, u, a_re, a_im);
    for (row = 0; row < 4; ++row) {
        for (column = 0; column < 4; ++column) {
            /* a' R a  with R = r_re + j*r_im, a' = conj(a) */
            double vr = r_re[row * 4 + column];
            double vi = r_im[row * 4 + column];
            double ar = a_re[row], ai = -a_im[row];
            double br = a_re[column], bi = a_im[column];
            /* (ar+jai)*(vr+jvi) */
            double pr = ar * vr - ai * vi;
            double pi_ = ar * vi + ai * vr;
            /* times (br+jbi) */
            total += pr * br - pi_ * bi;
        }
    }
    return total;
}

static int solve2(double m00, double m01, double m11, double b0, double b1,
                  double *x0, double *x1)
{
    double determinant = m00 * m11 - m01 * m01;
    if (fabs(determinant) < 1e-30) {
        return 1;
    }
    *x0 = (m11 * b0 - m01 * b1) / determinant;
    *x1 = (m00 * b1 - m01 * b0) / determinant;
    return 0;
}

int doa_wpi(const double *r_re, const double *r_im, double fc_hz,
            double dy_m, double dz_m, double *out_az_el)
{
    double p[4][2], baseline[6][2], phase[6], weight[6];
    double m00 = 0.0, m01 = 0.0, m11 = 0.0, b0 = 0.0, b1 = 0.0;
    double wave_number = 2.0 * PI * fc_hz / C_LIGHT;
    double uy, uz;
    int pair;

    positions(dy_m, dz_m, p);
    for (pair = 0; pair < 6; ++pair) {
        int first = PAIRS[pair][0], second = PAIRS[pair][1];
        double cross_re = r_re[second * 4 + first];
        double cross_im = r_im[second * 4 + first];
        double power = r_re[first * 4 + first] * r_re[second * 4 + second];
        double coherence = (cross_re * cross_re + cross_im * cross_im) /
                           (power > 1e-30 ? power : 1e-30);
        if (coherence > 0.999) coherence = 0.999;
        if (coherence < 0.001) coherence = 0.001;
        baseline[pair][0] = p[second][0] - p[first][0];
        baseline[pair][1] = p[second][1] - p[first][1];
        phase[pair] = atan2(cross_im, cross_re);
        weight[pair] = coherence / (1.0 - coherence);
        if (weight[pair] > 100.0) weight[pair] = 100.0;
        if (weight[pair] < 0.05) weight[pair] = 0.05;
    }
    for (pair = 0; pair < 6; ++pair) {
        m00 += weight[pair] * baseline[pair][0] * baseline[pair][0];
        m01 += weight[pair] * baseline[pair][0] * baseline[pair][1];
        m11 += weight[pair] * baseline[pair][1] * baseline[pair][1];
        b0 += weight[pair] * baseline[pair][0] * phase[pair];
        b1 += weight[pair] * baseline[pair][1] * phase[pair];
    }
    m00 += 1e-12;
    m11 += 1e-12;
    if (solve2(m00, m01, m11, -b0 / wave_number, -b1 / wave_number, &uy, &uz)) {
        return 1;
    }
    {
        double norm = sqrt(uy * uy + uz * uz);
        if (norm > 0.999999) {
            uy *= 0.999999 / norm;
            uz *= 0.999999 / norm;
        }
    }
    angles(uy, uz, &out_az_el[0], &out_az_el[1]);
    return 0;
}

/* dominant eigenvector of R by power iteration (4 steps, as in the MATLAB) */
static void dominant_vector(const double *r_re, const double *r_im,
                            const double start_re[4], const double start_im[4],
                            double v_re[4], double v_im[4])
{
    int iteration, row, column;
    for (row = 0; row < 4; ++row) {
        v_re[row] = start_re[row];
        v_im[row] = start_im[row];
    }
    for (iteration = 0; iteration < 4; ++iteration) {
        double next_re[4], next_im[4], norm = 0.0;
        for (row = 0; row < 4; ++row) {
            next_re[row] = 0.0;
            next_im[row] = 0.0;
            for (column = 0; column < 4; ++column) {
                double vr = r_re[row * 4 + column], vi = r_im[row * 4 + column];
                next_re[row] += vr * v_re[column] - vi * v_im[column];
                next_im[row] += vr * v_im[column] + vi * v_re[column];
            }
        }
        for (row = 0; row < 4; ++row) {
            norm += next_re[row] * next_re[row] + next_im[row] * next_im[row];
        }
        norm = sqrt(norm);
        if (norm < 1e-30) {
            norm = 1.0;
        }
        for (row = 0; row < 4; ++row) {
            v_re[row] = next_re[row] / norm;
            v_im[row] = next_im[row] / norm;
        }
    }
}

int doa_estimate(const double *r_re, const double *r_im, double fc_hz,
                 double dy_m, double dz_m, int gn_iterations, double *out_az_el)
{
    static const double STAGES[4] = {0.5, 0.1, 0.02, 0.005};
    double p[4][2], u[3], a_re[4], a_im[4];
    double wave_number = 2.0 * PI * fc_hz / C_LIGHT;
    double az_deg, el_deg;
    int stage, iteration;

    if (doa_wpi(r_re, r_im, fc_hz, dy_m, dz_m, out_az_el)) {
        return 1;
    }
    az_deg = out_az_el[0];
    el_deg = out_az_el[1];
    positions(dy_m, dz_m, p);

    /* 1. local ML: 4 stages of 3x3, 36 Bartlett evaluations */
    for (stage = 0; stage < 4; ++stage) {
        double step = STAGES[stage];
        double best = -1e300, best_az = az_deg, best_el = el_deg;
        int daz, del;
        for (daz = -1; daz <= 1; ++daz) {
            for (del = -1; del <= 1; ++del) {
                double candidate_az = az_deg + daz * step;
                double candidate_el = el_deg + del * step;
                double score;
                if (candidate_az < -55.0) candidate_az = -55.0;
                if (candidate_az > 55.0) candidate_az = 55.0;
                if (candidate_el < -45.0) candidate_el = -45.0;
                if (candidate_el > 45.0) candidate_el = 45.0;
                score = doa_bartlett(r_re, r_im, fc_hz, dy_m, dz_m,
                                     candidate_az, candidate_el);
                if (score > best) {
                    best = score;
                    best_az = candidate_az;
                    best_el = candidate_el;
                }
            }
        }
        az_deg = best_az;
        el_deg = best_el;
    }

    /* 2. Gauss-Newton on the same cost, with the projector of R */
    {
        double v_re[4], v_im[4];
        direction(az_deg, el_deg, u);
        steering(p, wave_number, u, a_re, a_im);
        dominant_vector(r_re, r_im, a_re, a_im, v_re, v_im);
        for (iteration = 0; iteration < gn_iterations; ++iteration) {
            double az = az_deg * RAD, el = el_deg * RAD;
            double du[2][3], gradient[2] = {0.0, 0.0};
            double h00 = 0.0, h01 = 0.0, h11 = 0.0;
            int basis, row;
            steering(p, wave_number, u, a_re, a_im);
            /* d u / d az and d u / d el */
            du[0][0] = -cos(el) * sin(az);
            du[0][1] = cos(el) * cos(az);
            du[0][2] = 0.0;
            du[1][0] = -sin(el) * cos(az);
            du[1][1] = -sin(el) * sin(az);
            du[1][2] = cos(el);
            {
                /* d = -j*k*(p.du).*a  and  pd = (I - v v') d ,  pa = (I - v v') a */
                double pa_re[4], pa_im[4], d_re[2][4], d_im[2][4], pd_re[2][4], pd_im[2][4];
                double vh_a_re = 0.0, vh_a_im = 0.0;
                for (row = 0; row < 4; ++row) {
                    vh_a_re += v_re[row] * a_re[row] + v_im[row] * a_im[row];
                    vh_a_im += v_re[row] * a_im[row] - v_im[row] * a_re[row];
                }
                for (row = 0; row < 4; ++row) {
                    double wr = v_re[row] * vh_a_re - v_im[row] * vh_a_im;
                    double wi = v_re[row] * vh_a_im + v_im[row] * vh_a_re;
                    pa_re[row] = a_re[row] - wr;
                    pa_im[row] = a_im[row] - wi;
                }
                for (basis = 0; basis < 2; ++basis) {
                    double vh_d_re = 0.0, vh_d_im = 0.0;
                    for (row = 0; row < 4; ++row) {
                        double proj = p[row][0] * du[basis][1] + p[row][1] * du[basis][2];
                        double scale = -wave_number * proj;
                        d_re[basis][row] = -scale * a_im[row];   /* j*scale*(a_re+j a_im) */
                        d_im[basis][row] = scale * a_re[row];
                        vh_d_re += v_re[row] * d_re[basis][row]
                                   + v_im[row] * d_im[basis][row];
                        vh_d_im += v_re[row] * d_im[basis][row]
                                   - v_im[row] * d_re[basis][row];
                    }
                    for (row = 0; row < 4; ++row) {
                        double wr = v_re[row] * vh_d_re - v_im[row] * vh_d_im;
                        double wi = v_re[row] * vh_d_im + v_im[row] * vh_d_re;
                        pd_re[basis][row] = d_re[basis][row] - wr;
                        pd_im[basis][row] = d_im[basis][row] - wi;
                    }
                    /* gradient = 2*Re(conj(d) * (P a)) */
                    {
                        double re = 0.0;
                        for (row = 0; row < 4; ++row) {
                            re += d_re[basis][row] * pa_re[row]
                                  + d_im[basis][row] * pa_im[row];
                        }
                        gradient[basis] = 2.0 * re;
                    }
                }
                /* Hessian = 2*Re(conj(d_i) * (P d_j)) */
                {
                    double h[2][2];
                    int row_index, column_index;
                    for (row_index = 0; row_index < 2; ++row_index) {
                        for (column_index = 0; column_index < 2; ++column_index) {
                            double re = 0.0;
                            for (row = 0; row < 4; ++row) {
                                re += d_re[row_index][row] * pd_re[column_index][row]
                                      + d_im[row_index][row] * pd_im[column_index][row];
                            }
                            h[row_index][column_index] = 2.0 * re;
                        }
                    }
                    h00 = h[0][0];
                    h01 = 0.5 * (h[0][1] + h[1][0]);
                    h11 = h[1][1];
                }
            }
            h00 += 1e-7;
            h11 += 1e-7;
            {
                double delta_az, delta_el, norm;
                if (solve2(h00, h01, h11, gradient[0], gradient[1],
                           &delta_az, &delta_el)) {
                    break;
                }
                delta_az *= DEG;
                delta_el *= DEG;
                norm = sqrt(delta_az * delta_az + delta_el * delta_el);
                if (norm > 0.05) {
                    delta_az *= 0.05 / norm;
                    delta_el *= 0.05 / norm;
                }
                az_deg -= delta_az;
                el_deg -= delta_el;
                if (az_deg < -55.0) az_deg = -55.0;
                if (az_deg > 55.0) az_deg = 55.0;
                if (el_deg < -45.0) el_deg = -45.0;
                if (el_deg > 45.0) el_deg = 45.0;
                direction(az_deg, el_deg, u);
            }
        }
    }
    out_az_el[0] = az_deg;
    out_az_el[1] = el_deg;
    return 0;
}
