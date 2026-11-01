from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "diagrams"
OUT.mkdir(parents=True, exist_ok=True)

FONT = "/usr/share/fonts/opentype/urw-base35/NimbusSans-Regular.otf"
BOLD = "/usr/share/fonts/opentype/urw-base35/NimbusSans-Bold.otf"

DIAGRAMS = {
    "01-overall-system": ("Complete calibrated 2x2 DOA homing chain", [
        ("RF source + paths", "waveform, loss, multipath"),
        ("2x2 array + RF ADC", "coupling, MTS, AGC, 14 bit"),
        ("PFB + detector", "1024 bins, CFAR, candidate"),
        ("DOA backend", "covariance, WPI, ML + GN"),
        ("EKF + homing", "navigation frame, guidance"),
    ]),
    "02-source-propagation": ("RF source and propagation model", [
        ("QAM/LFM/CW source", "complex baseband frame"),
        ("Free-space loss", "range and wavelength"),
        ("Direct steering", "actual element positions"),
        ("Reflected paths", "delay, gain, phase, angle"),
        ("Ideal antenna IQ", "8192 x 4 complex"),
    ]),
    "03-realistic-receiver": ("Realistic four-channel receiver and ADC", [
        ("Mutual coupling", "4 x 4 voltage matrix"),
        ("RF channel skew", "gain, phase, time, drift"),
        ("Noise + phase noise", "thermal and differential"),
        ("Common AGC", "preserves relative phase"),
        ("14-bit ADC", "clip and quantize"),
    ]),
    "04-rfdc-mts-interface": ("ZU48DR RFDC and deterministic stream interface", [
        ("Four RF inputs", "matched cables and LNAs"),
        ("RFDC + fine DDC", "2.048 GSPS, decimate 4"),
        ("MTS / SYSREF", "deterministic tile latency"),
        ("AXI gearbox", "4 samples per clock"),
        ("512-bit AXI stream", "128 MHz PL clock"),
    ]),
    "05-search-detection": ("Wideband search and source selection", [
        ("Polyphase FIR", "12 taps per band"),
        ("1024-point FFT", "2 MHz bin spacing"),
        ("Power + noise floor", "four-channel sum"),
        ("CA-CFAR", "training and guard cells"),
        ("Cluster + candidate", "center, BW, SNR gate"),
    ]),
    "06-calibration-covariance": ("Streaming calibration and covariance", [
        ("Q2.14 coefficients", "four complex corrections"),
        ("Calibrate 4 channels", "constant complex multiply"),
        ("4096 snapshots", "no sample-frame RAM"),
        ("4 powers + 6 pairs", "Hermitian covariance"),
        ("16 x int64 output", "AXI packet to PS"),
    ]),
    "07-weighted-phase": ("Six-baseline weighted phase interferometry", [
        ("Six cross phases", "angle of Rji"),
        ("Coherence weights", "gamma2 / (1-gamma2)"),
        ("2 x 2 normal matrix", "Y/Z baseline geometry"),
        ("Direction cosines", "solve uy and uz"),
        ("Azimuth/elevation seed", "known forward hemisphere"),
    ]),
    "08-ml-gn-refinement": ("Bounded local ML and Gauss-Newton polish", [
        ("WPI seed", "continuous initial angle"),
        ("36 ML candidates", "4 stages x 3 x 3"),
        ("Power iteration", "rank-one signal projector"),
        ("Two GN updates", "bounded 0.05 degree step"),
        ("Raw refined DOA", "off-grid measurement"),
    ]),
    "09-attitude-ekf": ("Full-attitude navigation-frame unit-vector EKF", [
        ("Body-frame DOA", "array measurement"),
        ("ZYX DCM", "yaw, pitch, roll"),
        ("6-state EKF", "LOS vector + rate"),
        ("Unit-sphere projection", "normalize and tangent rate"),
        ("Body-frame output", "inverse DCM for guidance"),
    ]),
    "10-platform-guidance": ("Detection-gated 3D homing guidance", [
        ("Valid candidate", "CFAR/SNR gate"),
        ("Filtered bearing", "wrapped azimuth innovation"),
        ("Rate-limited command", "yaw and pitch limits"),
        ("3D kinematics", "position and attitude"),
        ("Arrival decision", "true 1 x 3 range"),
    ]),
    "11-hil-flow": ("ZCU48DR hardware-in-the-loop verification", [
        ("MATLAB stimulus", "realistic IQ + int16 ADC pack"),
        ("AXI512 replay", "4 channels x 4 samples"),
        ("Covariance HLS IP", "calibrate and accumulate"),
        ("Board capture", "16 signed int64 values"),
        ("Exact + DOA compare", "integer match and <=0.1 deg"),
    ]),
    "12-pl-ps-partition": ("Recommended ZU48DR PL / PS partition", [
        ("PL streaming front end", "RFDC, PFB, CFAR"),
        ("PL covariance", "fixed point, II=1"),
        ("AXI-Lite / DMA", "16 covariance words"),
        ("R5F deterministic DOA", "WPI, ML, GN, EKF"),
        ("A53 supervision", "calibration, logs, network"),
    ]),
}


def font(path, size):
    return ImageFont.truetype(path, size)


def arrow(draw, x1, y1, x2, y2, color):
    draw.line((x1, y1, x2, y2), fill=color, width=5)
    draw.polygon([(x2, y2), (x2 - 15, y2 - 10), (x2 - 15, y2 + 10)], fill=color)


def render(name, title, stages):
    width, height = 1600, 440
    image = Image.new("RGB", (width, height), "white")
    draw = ImageDraw.Draw(image)
    navy, blue, pale, gray = "#17324D", "#246B9E", "#EAF3F8", "#52606D"
    draw.text((60, 35), title, font=font(BOLD, 38), fill=navy)
    draw.text((60, 88), "Signal flow from left to right", font=font(FONT, 23), fill=gray)
    margin, gap = 60, 28
    box_width = (width - 2 * margin - gap * (len(stages) - 1)) // len(stages)
    y1, y2 = 150, 350
    for index, (heading, detail) in enumerate(stages):
        x1 = margin + index * (box_width + gap)
        x2 = x1 + box_width
        draw.rounded_rectangle((x1, y1, x2, y2), radius=18, fill=pale, outline=blue, width=4)
        heading_box = draw.textbbox((0, 0), heading, font=font(BOLD, 25))
        heading_width = heading_box[2] - heading_box[0]
        draw.text((x1 + (box_width - heading_width) / 2, y1 + 42), heading,
                  font=font(BOLD, 25), fill=navy)
        detail_box = draw.multiline_textbbox((0, 0), detail, font=font(FONT, 21), align="center")
        detail_width = detail_box[2] - detail_box[0]
        draw.multiline_text((x1 + (box_width - detail_width) / 2, y1 + 105), detail,
                            font=font(FONT, 21), fill=gray, align="center", spacing=4)
        if index < len(stages) - 1:
            arrow(draw, x2 + 4, (y1 + y2) // 2, x2 + gap - 4, (y1 + y2) // 2, blue)
    draw.text((60, 395), "DOA 2x2 Realistic HIL V7 | MATLAB R2024a | XCZU48DR",
              font=font(FONT, 19), fill=gray)
    image.save(OUT / f"{name}.jpg", quality=94, subsampling=0)


for filename, (diagram_title, diagram_stages) in DIAGRAMS.items():
    render(filename, diagram_title, diagram_stages)

print(f"Generated {len(DIAGRAMS)} diagrams in {OUT}")
