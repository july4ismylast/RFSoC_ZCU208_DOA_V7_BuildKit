/* doa_core.h -- the R5F direction estimator, in plain C, no dependencies.
 *
 * This is the code that would run on the Cortex-R5F.  It is deliberately
 * double-precision and allocation-free: every buffer is on the caller's stack,
 * and the only library call is atan2/asin/sqrt from libm.
 *
 * The chain (V07 sections 6-7):
 *
 *   1  WPI         six baseline phases -> weighted least squares -> (az, el)
 *   2  ML grid     4 stages x 3x3 = 36 evaluations of a'Ra around the WPI seed
 *   3  Gauss-Newton 2 steps on the same cost, using the projector of R
 *
 * All angles in degrees, all frequencies in Hz, all lengths in metres.
 */

#ifndef DOA_CORE_H
#define DOA_CORE_H

/* 2x2 array: CH1..CH4 at
 *   (-dy/2,-dz/2)  (+dy/2,-dz/2)  (-dy/2,+dz/2)  (+dy/2,+dz/2)
 * r_re/r_im are 4x4 row-major covariance parts.
 */
int doa_wpi(const double *r_re, const double *r_im, double fc_hz,
            double dy_m, double dz_m, double *out_az_el);

/* The full chain.  gn_iterations = 2 is what V07 uses. */
int doa_estimate(const double *r_re, const double *r_im, double fc_hz,
                 double dy_m, double dz_m, int gn_iterations, double *out_az_el);

/* Bartlett score at one direction, exposed for the test bench. */
double doa_bartlett(const double *r_re, const double *r_im, double fc_hz,
                    double dy_m, double dz_m, double az_deg, double el_deg);

#endif
