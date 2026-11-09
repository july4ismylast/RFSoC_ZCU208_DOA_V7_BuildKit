#ifndef PIR_HOST_SHIM_HLS_STREAM_H
#define PIR_HOST_SHIM_HLS_STREAM_H
// Minimal blocking FIFO standing in for hls::stream in host tests: read() on an
// empty stream aborts, mirroring the deadlock a real C simulation would show.
#include <cstdio>
#include <cstdlib>
#include <deque>

namespace hls {

template <class T>
class stream {
public:
    void write(const T& value) { queue_.push_back(value); }

    T read() {
        if (queue_.empty()) {
            std::fprintf(stderr, "HOST SHIM: read() on empty hls::stream (the real C-sim would stall)\n");
            std::exit(3);
        }
        T value = queue_.front();
        queue_.pop_front();
        return value;
    }

    bool empty() const { return queue_.empty(); }
    std::size_t size() const { return queue_.size(); }

private:
    std::deque<T> queue_;
};

}  // namespace hls

#endif
