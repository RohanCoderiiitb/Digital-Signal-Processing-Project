# Wideband FM Reception and Denoising with RTL-SDR

A five-stage MATLAB software-defined-radio pipeline that scans the 88–108 MHz commercial FM band with an RTL-SDR dongle, captures raw I/Q from an assigned station, isolates the channel with FIR and IIR low-pass filters, demodulates it to audio, and denoises the result with a Wiener filter — with time-frequency analysis at every stage.

---

## Table of Contents

- [Overview](#overview)
- [Repository Structure](#repository-structure)
- [Requirements](#requirements)
- [Signal Chain](#signal-chain)
- [Task 1 — Wideband Scanner and Station Identification](#task-1--wideband-scanner-and-station-identification)
- [Task 2 — Data Acquisition and Baseline Demodulation](#task-2--data-acquisition-and-baseline-demodulation)
- [Task 3 — Baseband Low-Pass Filtering (FIR vs IIR)](#task-3--baseband-low-pass-filtering-fir-vs-iir)
- [Task 4 — Optimal Denoising via Wiener Filtering](#task-4--optimal-denoising-via-wiener-filtering)
- [Task 5 — Time-Frequency Analysis (STFT)](#task-5--time-frequency-analysis-stft)
- [How to Run](#how-to-run)
- [Key Parameters](#key-parameters)
- [Known Limitations](#known-limitations)

---

## Overview

| | |
|---|---|
| **Hardware** | RTL-SDR USB receiver (`comm.SDRRTLReceiver`) |
| **Sample rate** | 2.4 MSPS complex I/Q |
| **Scanned band** | 88 – 108 MHz (WBFM broadcast) |
| **Assigned station** | 101.305 MHz (selected by `mod(rollNumber, 5) + 1`) |
| **Capture length** | 10 s of raw I/Q (24 M complex samples) |
| **Audio output** | 48 kHz mono WAV |
| **Environment** | MATLAB R2023b+ |

The project demonstrates a complete receive chain: **acquire → isolate → demodulate → denoise → analyse**, and quantifies the trade-off between filter efficiency and phase integrity along the way.

---

## Repository Structure

```
.
├── Project.m                     # Full MATLAB pipeline (Tasks 1–5)
├── README.md
├── docs/
│   ├── Presentation.pptx         # Project presentation
│   ├── Task_3_Analysis.txt       # FIR vs IIR technical discussion
│   └── Task_4_Analysis.txt       # Wiener denoising subjective analysis
├── data/
│   └── Task_2_Raw_IQ_Data_<timestamp>.mat   # Raw I/Q capture (-v7.3, large)
├── audio/
│   ├── Task_2_IQ_Demod_Init_<timestamp>.wav # Baseline demodulated audio
│   └── Task_4_Denoised_Demod_Audio.wav      # Wiener-denoised audio
└── figures/
    ├── Task_1_Power_Spectrum.png
    ├── Task_1_Top_5.png
    ├── Task_2_Time_Domain_IQ.png
    ├── Task_3_Filter_and_Phase_Responses.png
    ├── Task_3_Spectrogram_Comparison.png
    ├── Task_3_Table.png
    ├── Task_4_Power_Spectrum_Comparison.png
    ├── Task_5_STFT_Spectrograms.png
    └── Task_5_Waveform_Comparison.png
```

> **Note:** the raw `.mat` capture is ~80 MB and exceeds GitHub's comfortable file size. Consider Git LFS, or exclude `data/` via `.gitignore` and regenerate it by re-running Task 2.

---

## Requirements

- MATLAB R2023b or later
- [Signal Processing Toolbox](https://www.mathworks.com/products/signal.html) — `pwelch`, `fir1`, `cheby2`, `freqz`, `spectrogram`, `stft`, `findpeaks`
- [Communications Toolbox](https://www.mathworks.com/products/communications.html) — `comm.FMBroadcastDemodulator`
- [Communications Toolbox Support Package for RTL-SDR Radio](https://www.mathworks.com/hardware-support/rtl-sdr.html) — `comm.SDRRTLReceiver`
- An RTL-SDR dongle with a VHF-capable antenna (**only required for Tasks 1–2**; Tasks 3–5 run offline from the saved `.mat` file)

---

## Signal Chain

```
RTL-SDR ──► 2.4 MSPS I/Q ──► 100 kHz LPF ──► WBFM Demod ──► Wiener Filter ──► 48 kHz Audio
  (T1/T2)                       (T3)            (T4)            (T4)              (T5 analysis)
```

---

## Task 1 — Wideband Scanner and Station Identification

The receiver steps across the FM band in **2 MHz increments from 89 MHz to 107 MHz**, deliberately overlapping adjacent 2.4 MHz captures so no part of the band falls in a tuner roll-off region. At each step the local oscillator is allowed to settle by flushing five frames before a measurement frame is captured.

Each frame's power spectral density is estimated with **Welch's method** (1024-point FFT, 512-sample overlap, centered) and converted to dBm/Hz. The stitched spectra are sorted, de-duplicated at the overlap seams, and passed to `findpeaks` with a **200 kHz minimum peak separation** — matching standard FM channel spacing — to recover the five strongest carriers.

The station under study is then chosen deterministically from the roll number:

```matlab
stationIndex = mod(rollNumber, 5) + 1;   % 238 → index 4 → 101.305 MHz
```

**Deliverable 1.1 — Power spectrum of the FM broadcast band with the top 5 peaks annotated**

<!-- Replace with the actual path once figures are committed -->
<img width="1179" height="731" alt="Task_1_Power_Spectrum" src="https://github.com/user-attachments/assets/9bd532ca-86f1-4e0a-9de3-b1e8c305193f" />


**Deliverable 1.2 — Console output: discovered stations and index assignment**

<img width="383" height="292" alt="Task_1_Top_5" src="https://github.com/user-attachments/assets/536f32c5-fdcd-44c5-b532-27b00f463a08" />


| Index | Center Frequency | Est. Bandwidth |
|:-----:|:----------------:|:--------------:|
| 1 | 91.087 MHz | ~200 kHz |
| 2 | 95.000 MHz | ~200 kHz |
| 3 | 98.320 MHz | ~200 kHz |
| **4** | **101.305 MHz** ← assigned | ~200 kHz |
| 5 | 102.918 MHz | ~200 kHz |

---

## Task 2 — Data Acquisition and Baseline Demodulation

The SDR is retuned to the assigned carrier and **10 seconds of raw complex I/Q** are recorded in 0.1 s frames into a pre-allocated buffer. The capture is timestamped at the moment recording begins and saved with `-v7.3` (24 M double-precision complex samples exceed the classic MAT-file 2 GB limit).

Demodulation uses `comm.FMBroadcastDemodulator` at a 48 kHz audio rate and is performed **chunk-by-chunk** over the same 0.1 s frame size, keeping peak memory bounded rather than passing the entire 24 M-sample vector at once. The output is peak-normalised before being written to WAV to avoid clipping.

**Deliverable 2.2** — Baseline audio: [Task_2_IQ_Demod_Init_2026-03-29_09-01-06.wav](https://github.com/user-attachments/files/31120226/Task_2_IQ_Demod_Init_2026-03-29_09-01-06.wav)


**Deliverable 2.3 — Time-domain magnitude |I + jQ| of the raw capture**

<img width="1054" height="597" alt="Task_2_Time_Domain_IQ" src="https://github.com/user-attachments/assets/4446b4db-d735-4866-9b78-d2742746afa1" />


The envelope hovers near a constant amplitude — as expected for a frequency-modulated carrier, where information is carried in the phase rather than the magnitude. The downward spikes are AGC transients and noise-driven envelope dropouts.

---

## Task 3 — Baseband Low-Pass Filtering (FIR vs IIR)

Two low-pass filters are designed to the same magnitude specification and applied to the identical raw I/Q record, isolating the 200 kHz WBFM channel (100 kHz of baseband bandwidth) from its neighbours.

| | FIR | IIR |
|---|---|---|
| Method | Window method (`fir1`, Hann window) | Analog prototype (`cheby2`, Chebyshev Type II) |
| Order | 100 | 12 |
| Cutoff | 100 kHz | 100 kHz |
| Stopband | Set by window sidelobes | 60 dB |

**Deliverable 3.1 — Magnitude and phase responses**

<img width="1750" height="794" alt="Task_3_Filter_and_Phase_Responses" src="https://github.com/user-attachments/assets/10d0ea46-cfc8-4839-89a9-e30bef01146b" />


The 12th-order IIR achieves a visibly sharper transition band than the 100-tap FIR at a fraction of the computational cost — but the phase plot tells the other half of the story. The FIR traces a perfectly straight line across the passband (constant group delay), while the IIR curves and eventually wraps.

**Deliverable 3.2 — Comparative spectrograms of a 50 ms slice**

<img width="1748" height="773" alt="Task_3_Spectrogram_Comparison" src="https://github.com/user-attachments/assets/dfec0105-cec0-4332-8c92-c3fa6bb63816" />


Subplot (a) shows the centered but unfiltered baseband, with adjacent-channel energy spread across the full ±1.2 MHz span. Both filtered versions collapse that energy into the isolated channel around DC, dropping the out-of-band noise floor by roughly 20–30 dB.

**Technical discussion**

<img width="791" height="287" alt="Task_3_Table" src="https://github.com/user-attachments/assets/6548987b-77cd-4663-a1ca-e24d759ddb19" />


| Feature | FIR (Window Method) | IIR (Analog Prototype) |
|---|---|---|
| Phase response | Linear (straight) | Non-linear (curved) |
| Group delay | Constant | Varying |
| Integrity | High — no phase distortion | Lower — phase distortion |
| Efficiency | Lower — requires high order | Higher — requires low order |

Because FM demodulation recovers information from the **time derivative of the phase**, any phase nonlinearity in the channel filter becomes group delay distortion — "phase smearing" — that degrades transient clarity in the recovered audio. The FIR filter delays every spectral component within the 100 kHz channel equally, preserving temporal consistency at the cost of a higher order. **The FIR output is therefore the one carried forward into Task 4.**

---

## Task 4 — Optimal Denoising via Wiener Filtering

The FIR-isolated I/Q is demodulated to 48 kHz audio, which still carries a wideband noise floor — the characteristic FM "hiss". A Wiener filter is then constructed from the signal's own statistics:

1. **Noise PSD `Pnn`** — estimated by Welch from a 100 ms slice assumed to contain background hiss only.
2. **Observed PSD `Pyy`** — estimated by Welch over the full audio record.
3. **Clean-signal PSD** — `Pss = max(0, Pyy − Pnn)`, clamped to reject negative power estimates.
4. **Transfer function** — `H(f) = Pss / (Pss + Pnn)`, which approaches 1 where signal dominates and 0 where noise dominates.
5. **Application** — `H(f)` is interpolated onto the full FFT grid, forced to conjugate symmetry so the inverse transform is real-valued, applied in the frequency domain, and the result is peak-normalised.

**Deliverable 4.1 — Power spectrum before and after denoising**

<img width="1750" height="794" alt="Task_4_Power_Spectrum_Comparison" src="https://github.com/user-attachments/assets/10f124f2-bf78-4d74-b455-3f154a340e39" />


The filter leaves the speech-dominant region below ~5 kHz essentially untouched while carving deep nulls into bins where noise power dominates the estimate.

**Deliverable 4.2** — Denoised audio: [Task_4_Denoised_Demod_Audio.wav](https://github.com/user-attachments/files/31120250/Task_4_Denoised_Demod_Audio.wav)


Subjectively, background static is virtually eliminated during pauses in speech, raising perceived SNR without introducing significant "musical noise" artifacts.

---

## Task 5 — Time-Frequency Analysis (STFT)

The three stages of the audio chain are compared in the time-frequency plane using an STFT with a **1024-sample Hamming window, 512-sample overlap, and 1024-point FFT**, displayed over the 0–20 kHz audible range.

**Deliverable 5.1 — STFT spectrograms across the processing chain**

<img width="1047" height="975" alt="Task_5_STFT_Spectrograms" src="https://github.com/user-attachments/assets/3521a331-df60-4881-bfd7-af59655d778f" />


- **(a) Original demodulated (pre-LPF)** — broadband energy fills the full 0–20 kHz span, including the interval near t ≈ 6 s where the broadcast itself is quiet.
- **(b) After LPF isolation** — the quiet interval now reads as genuine silence; adjacent-channel interference has been removed.
- **(c) After Wiener filtering** — the high-frequency hiss above ~7 kHz is strongly suppressed while harmonic structure in the speech band survives intact.

**Deliverable 5.2 — Waveform detail (50 ms window at t = 1.00–1.05 s)**

<img width="1060" height="720" alt="Task_5_Waveform_Comparison" src="https://github.com/user-attachments/assets/b2e1e5fb-bc6f-442b-8bf3-bd15367e6f86" />


Zoomed to a 50 ms segment, the pre-Wiener trace carries dense high-frequency jitter riding on the speech envelope; post-Wiener, the underlying modulation envelope is far more clearly resolved.

---

## How to Run

```matlab
% 1. Clone and open in MATLAB
%    Tasks 1–2 require an RTL-SDR dongle connected via USB.

% 2. Set your roll number at the top of Project.m
rollNumber = 238;

% 3. Run Tasks 1–2 to scan the band and capture I/Q.
%    Note the timestamp printed to the console.

% 4. Update the filename in Task 3 to match your capture:
filename = 'Task_2_Raw_IQ_Data_<your_timestamp>.mat';

% 5. Run Tasks 3–5 offline — no hardware needed.
```

To reproduce Tasks 3–5 from the archived capture without any hardware, place the provided `.mat` file in the working directory and run the script from the Task 3 section onward.

---

## Key Parameters

| Parameter | Value | Set in |
|---|---|---|
| `Fs` | 2.4 MSPS | All tasks |
| `audioFs` | 48 kHz | Tasks 2, 4, 5 |
| `captureDuration` | 10 s | Task 2 |
| Scan step | 2 MHz (89 → 107 MHz) | Task 1 |
| Welch window / overlap / NFFT | 1024 / 512 / 1024 | Tasks 1, 4 |
| `MinPeakDistance` | 200 kHz | Task 1 |
| FIR order / window | 100 / Hann | Task 3 |
| IIR order / stopband | 12 / 60 dB (Chebyshev II) | Task 3 |
| LPF cutoff | 100 kHz | Task 3 |
| Noise-estimation slice | First 100 ms | Task 4 |
| STFT window / overlap / NFFT | 1024 Hamming / 512 / 1024 | Task 5 |

---

## Known Limitations

- **Absolute power calibration.** PSD values are reported in dBm/Hz assuming a 1 Ω reference and no correction for antenna gain, cable loss, or the tuner AGC — figures are useful for relative comparison between stations, not as calibrated field-strength measurements.
- **Stationary noise assumption.** The Wiener filter estimates the noise PSD once, from the first 100 ms of audio. If that window contains speech, or if the noise character changes over the record, the transfer function will be mis-shaped for the rest of the signal. A per-frame (adaptive) estimate would be more robust.
- **Filter transients.** `filter()` is used rather than `filtfilt()`, so the FIR's ~50-sample group delay is present in the output; downstream comparisons are not delay-compensated.
- **Overlap seams.** Concatenating swept PSD segments can leave small discontinuities at the stitch points, visible as steps in the wideband spectrum plot.

---
