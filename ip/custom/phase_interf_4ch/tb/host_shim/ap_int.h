#ifndef PIR_HOST_SHIM_AP_INT_H
#define PIR_HOST_SHIM_AP_INT_H
// -----------------------------------------------------------------------------
// Minimal host shim for the tiny subset of <ap_int.h> used by
// phase_interf_4ch.cpp and tb/phase_interf_4ch_tb.cpp.
//
// WHY THIS EXISTS
//   The Vitis HLS C-simulation testbench cannot be run on a machine without
//   Vitis.  This shim lets the *same* kernel source and the *same* testbench be
//   compiled with g++ on any host, so the AXI packing, the 16-word output order,
//   the phase-record layout and the frame-tag echo are executed and checked
//   before anyone spends a Vitis licence on them.
//
// WHAT IT IS NOT
//   Not cycle accurate, not a scheduling model, no saturation or overflow
//   semantics, no ap_fixed, widths above 64 bits only for storage/range access
//   (ap_uint<512>), and arithmetic is plain two's complement in 64 bits.  It
//   cannot replace `csim_design`/`csynth_design`; it only proves the code runs,
//   compiles as C++11/14 and produces the expected record.
//
// SCOPE
//   ap_uint<W>, ap_int<W> for W <= 64 with arbitrary bit ranges, plus
//   ap_uint<512> style storage for AXI words; conversions, comparisons,
//   +, *, <<, |, &, assignment and range get/set.
// -----------------------------------------------------------------------------

#include <array>
#include <cstdint>
#include <type_traits>

template <int W> class ap_int;
template <int W> class ap_uint;

namespace pir_shim {

template <class T> struct is_ap_int : std::false_type {};
template <int W> struct is_ap_int<ap_int<W>> : std::true_type {};
template <int W> struct is_ap_int<ap_uint<W>> : std::true_type {};

// Value extraction used by bit-slice assignment; declared before bit_proxy so
// the dependent call inside its template resolves at definition time.
template <class T, typename std::enable_if<std::is_integral<T>::value, int>::type = 0>
inline unsigned long long to_ull(T value) {
    return static_cast<unsigned long long>(static_cast<long long>(value));
}
template <int W>
inline unsigned long long to_ull(const ap_uint<W>& value) { return value.to_uint64(); }
template <int W>
inline unsigned long long to_ull(const ap_int<W>& value) {
    return static_cast<unsigned long long>(value.to_int64());
}

template <int W>
struct bit_storage {
    static constexpr int kWords = (W + 63) / 64;
    std::array<std::uint64_t, kWords> words{{}};

    std::uint64_t get(int hi, int lo) const {
        const int span = hi - lo + 1;
        const int index = lo / 64;
        const int offset = lo % 64;
        std::uint64_t value = words[index] >> offset;
        if (offset + span > 64 && index + 1 < kWords) {
            value |= words[index + 1] << (64 - offset);
        }
        const std::uint64_t mask =
            (span >= 64) ? ~static_cast<std::uint64_t>(0)
                         : ((static_cast<std::uint64_t>(1) << span) - 1);
        return value & mask;
    }

    void set(int hi, int lo, std::uint64_t value) {
        const int span = hi - lo + 1;
        const int index = lo / 64;
        const int offset = lo % 64;
        const std::uint64_t mask =
            (span >= 64) ? ~static_cast<std::uint64_t>(0)
                         : ((static_cast<std::uint64_t>(1) << span) - 1);
        const std::uint64_t payload = value & mask;
        words[index] = (words[index] & ~(mask << offset)) | (payload << offset);
        if (offset + span > 64 && index + 1 < kWords) {
            const int carry = 64 - offset;
            words[index + 1] = (words[index + 1] & ~(mask >> carry)) | (payload >> carry);
        }
    }
};

template <class Owner>
class bit_proxy {
public:
    bit_proxy(Owner& owner, int hi, int lo) : owner_(owner), hi_(hi), lo_(lo) {}

    template <class T>
    operator T() const {                       // get, e.g. (ap_int<16>)word.range(15,0)
        return T(static_cast<long long>(owner_.raw(hi_, lo_)));
    }

    template <class T>
    bit_proxy& operator=(const T& value) {     // set, e.g. word.range(...) = packed
        owner_.assign(hi_, lo_, to_ull(value));
        return *this;
    }

private:
    Owner& owner_;
    int hi_;
    int lo_;
};


}  // namespace pir_shim

template <int W>
class ap_uint {
public:
    ap_uint() = default;

    template <class T, typename std::enable_if<std::is_integral<T>::value, int>::type = 0>
    ap_uint(T value) { assign(static_cast<long long>(value)); }

    template <int Other>
    ap_uint(const ap_uint<Other>& other) { assign(static_cast<long long>(other.to_uint64())); }

    template <int Other>
    ap_uint(const ap_int<Other>& other) { assign(other.to_int64()); }

    template <class T, typename std::enable_if<std::is_integral<T>::value, int>::type = 0>
    ap_uint& operator=(T value) { assign(static_cast<long long>(value)); return *this; }

    unsigned long long to_uint64() const { return storage_.get(W - 1, 0); }
    unsigned int to_uint() const { return static_cast<unsigned int>(to_uint64()); }

    pir_shim::bit_proxy<ap_uint<W>> range(int hi, int lo) {
        return pir_shim::bit_proxy<ap_uint<W>>(*this, hi, lo);
    }
    std::uint64_t raw(int hi, int lo) const { return storage_.get(hi, lo); }
    void assign(int hi, int lo, std::uint64_t value) { storage_.set(hi, lo, value); }

    friend bool operator==(const ap_uint& a, const ap_uint& b) { return a.to_uint64() == b.to_uint64(); }
    friend bool operator!=(const ap_uint& a, const ap_uint& b) { return !(a == b); }
    friend bool operator==(const ap_uint& a, long long b) { return a.to_uint64() == static_cast<unsigned long long>(b); }
    friend bool operator!=(const ap_uint& a, long long b) { return !(a == b); }

    friend ap_uint operator<<(const ap_uint& a, int shift) { return ap_uint(a.to_uint64() << shift); }
    friend ap_uint operator>>(const ap_uint& a, int shift) { return ap_uint(a.to_uint64() >> shift); }
    template <int Other>
    friend ap_uint operator|(const ap_uint& a, const ap_uint<Other>& b) {
        return ap_uint(a.to_uint64() | b.to_uint64());
    }
    template <int Other>
    friend ap_uint operator&(const ap_uint& a, const ap_uint<Other>& b) {
        return ap_uint(a.to_uint64() & b.to_uint64());
    }

private:
    void assign(long long value) {
        storage_ = pir_shim::bit_storage<W>();
        storage_.set(W - 1, 0, static_cast<std::uint64_t>(value));
    }
    pir_shim::bit_storage<W> storage_;
};

template <int W>
class ap_int {
    static_assert(W <= 64, "host shim supports signed widths up to 64 bits");

public:
    ap_int() = default;

    template <class T, typename std::enable_if<std::is_integral<T>::value, int>::type = 0>
    ap_int(T value) : value_(static_cast<long long>(value)) {}

    template <int Other>
    ap_int(const ap_int<Other>& other) : value_(other.to_int64()) {}

    template <int Other>
    ap_int(const ap_uint<Other>& other)
        : value_(signed_from_bits(other.to_uint64())) {}

    template <class T, typename std::enable_if<std::is_integral<T>::value, int>::type = 0>
    ap_int& operator=(T value) { value_ = static_cast<long long>(value); return *this; }

    long long to_int64() const { return value_; }
    int to_int() const { return static_cast<int>(value_); }

    ap_int& operator+=(const ap_int& other) { value_ += other.value_; return *this; }
    ap_int& operator-=(const ap_int& other) { value_ -= other.value_; return *this; }

    friend ap_int operator+(const ap_int& a, const ap_int& b) { return ap_int(a.value_ + b.value_); }
    friend ap_int operator-(const ap_int& a, const ap_int& b) { return ap_int(a.value_ - b.value_); }
    friend ap_int operator*(const ap_int& a, const ap_int& b) { return ap_int(a.value_ * b.value_); }

    friend bool operator==(const ap_int& a, const ap_int& b) { return a.value_ == b.value_; }
    friend bool operator!=(const ap_int& a, const ap_int& b) { return a.value_ != b.value_; }

private:
    static long long signed_from_bits(unsigned long long bits) {
        const unsigned long long signBit = static_cast<unsigned long long>(1) << (W - 1);
        const unsigned long long mask = (W >= 64) ? ~static_cast<unsigned long long>(0)
                                                 : ((static_cast<unsigned long long>(1) << W) - 1);
        const unsigned long long truncated = bits & mask;
        if (truncated & signBit) {
            return static_cast<long long>(truncated | ~mask);
        }
        return static_cast<long long>(truncated);
    }
    long long value_ = 0;
};

#endif  // PIR_HOST_SHIM_AP_INT_H
