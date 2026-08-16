%% SDR Lab Assignment: FM Spectrum Sweep and Demodulation
clear; clc; close all;

% --- USER INPUTS ---
rollNumber = 238; % Replace with your actual numeric roll number
captureDuration = 10; %#ok<NASGU> % Duration to record raw I/Q in seconds
Fs = 2.4e6;           % SDR Sample Rate (2.4 MSPS)

disp('Starting Wideband FM Scanner...');

    %% ========================================================================
    % TASK 1: WIDEBAND SCANNER & STATION IDENTIFICATION
    % ========================================================================
    
    % 1. Set up the RTL-SDR Receiver
    sdr = comm.SDRRTLReceiver(...
        'CenterFrequency', 89e6, ... 
        'SampleRate', Fs, ...
        'EnableTunerAGC', true, ...
        'SamplesPerFrame', Fs * 0.1, ... % Capture 0.1s frames
        'OutputDataType', 'double');     % Direct to double for pwelch
    
    % Sweep parameters for the FM Band
    % We step by 2 MHz to ensure overlap and cover the 88-108 MHz band safely
    scanFreqs = 89e6 : 2e6 : 107e6; 
    
    all_PSD = [];
    all_Freqs = [];
    
    disp('Sweeping 88 - 108 MHz band... Please wait.');
    
    for fc = scanFreqs
        sdr.CenterFrequency = fc;
        
        % Flush buffer (allow the local oscillator to settle)
        for k = 1:5
            rxData = sdr();
        end
        
        % Capture frame for PSD analysis
        rxData = sdr();
        
        % Compute Power Spectral Density using Welch's method
        [pxx, f] = pwelch(rxData, 1024, 512, 1024, Fs, 'centered');
        
        % Convert to dBm (assuming 1 ohm reference, standard for SDR labs)
        pxx_dBm = 10*log10(pxx) + 30; 
        
        % Append to global array
        all_PSD = [all_PSD; pxx_dBm];
        all_Freqs = [all_Freqs; f + fc];
    end
    
    % Clean up concatenated frequencies: Sort and remove duplicates
    % (Overlapping sweeps create duplicate bins which crashes findpeaks)
    [all_Freqs, uniqueIdx] = unique(all_Freqs);
    all_PSD = all_PSD(uniqueIdx);
    
    % 2. Identify Top 5 Stations (Peaks)
    % Minimum distance of 200 kHz (Standard FM channel spacing)
    [pks, locs] = findpeaks(all_PSD, all_Freqs, ...
        'MinPeakDistance', 200e3, 'SortStr', 'descend');
    
    % Extract Top 5 and sort them chronologically by frequency
    top5_Freqs = locs(1:5);
    top5_PSD = pks(1:5);
    [top5_Freqs_sorted, sort_idx] = sort(top5_Freqs);
    top5_PSD_sorted = top5_PSD(sort_idx);
    
    % 3. Calculate Assigned Station Index
    stationIndex = mod(rollNumber, 5) + 1;
    assigned_fc = top5_Freqs_sorted(stationIndex);
    
    % --- Deliverable 1.1: Power Spectrum Plot ---
    figure('Name', 'Wideband FM Spectrum', 'NumberTitle', 'off', 'Position', [100, 100, 900, 500]);
    plot(all_Freqs / 1e6, all_PSD, 'b');
    hold on;
    plot(top5_Freqs_sorted / 1e6, top5_PSD_sorted, 'ro', 'MarkerSize', 8, 'LineWidth', 2);
    
    % Label the top 5 peaks
    for i = 1:5
        text(top5_Freqs_sorted(i)/1e6, top5_PSD_sorted(i) + 2, ...
            sprintf('  #%d: %.1f MHz', i, top5_Freqs_sorted(i)/1e6), ...
            'Color', 'r', 'FontSize', 10, 'FontWeight', 'bold');
    end
    title('Deliverable 1: Power Spectrum of FM Broadcast Band (88-108 MHz)');
    xlabel('Frequency (MHz)');
    ylabel('Power Spectral Density (dBm/Hz)');
    grid on; hold off;
    
    % --- Deliverable 1.2 & 1.3: Console Outputs & Tabulation ---
    fprintf('\n--- TASK 1 RESULTS ---\n');
    fprintf('Roll Number: %d\n', rollNumber);
    fprintf('Calculated Index: (mod(%d, 5)) + 1 = %d\n', rollNumber, stationIndex);
    
    fprintf('\nTop 5 Discovered Stations:\n');
    fprintf('Index\t Center Freq (fc)\t Bandwidth (Est)\n');
    fprintf('--------------------------------------------------\n');
    for i = 1:5
        fprintf('%d\t\t %.3f MHz\t\t ~200 kHz\n', i, top5_Freqs_sorted(i)/1e6);
    end
    fprintf('\n>>> ASSIGNED STATION: %.3f MHz (Index %d) <<<\n', assigned_fc/1e6, stationIndex);

    %% ========================================================================
    %  TASK 2 - DATA ACQUISITION AND RAW DEMODULATION
    % ========================================================================

% --- USER INPUTS ---
fc = 101.305e6;          % Assigned station frequency in Hz (from Task 1)
Fs = 2.4e6;            % SDR Sample Rate (2.4 MSPS)
captureDuration = 10;  % Duration to record in seconds

disp(['Starting Task 2: Tuning to ', num2str(fc/1e6), ' MHz...']);

try
    % 1. Set up the RTL-SDR Receiver
    sdr = comm.SDRRTLReceiver(...
        'CenterFrequency', fc, ... 
        'SampleRate', Fs, ...
        'EnableTunerAGC', true, ...
        'SamplesPerFrame', Fs * 0.1, ... % Capture 0.1s frames
        'OutputDataType', 'double');
    
    % Pre-allocate memory for the raw I/Q capture
    totalSamples = Fs * captureDuration;
    rawIQ = complex(zeros(totalSamples, 1));
    
    % Flush buffer to allow the local oscillator to settle on the new frequency
    for k = 1:5
        temp = sdr();
    end
    
    % 2. Capture the Raw I/Q Data
    disp(['Recording ', num2str(captureDuration), ' seconds of raw I/Q data...']);
    
    % Get timestamp exactly when recording starts
    timeStamp = char(datetime('now', 'Format', 'yyyy-MM-dd_HH-mm-ss'));
    
    framesToCapture = captureDuration / 0.1;
    idx = 1;
    for k = 1:framesToCapture
        frameData = sdr();
        rawIQ(idx : idx + length(frameData) - 1) = frameData;
        idx = idx + length(frameData);
    end
    
    % Release the hardware immediately after capture
    release(sdr);
    disp('Recording complete.');
    
    % 3. Save Raw I/Q Data (Deliverable 1)
    rawFilename = sprintf('Raw_IQ_Data_%s.mat', timeStamp);
    % Using -v7.3 because 24 million double-precision complex samples exceeds 2GB
    save(rawFilename, 'rawIQ', 'Fs', 'fc', 'timeStamp', '-v7.3'); 
    fprintf('Deliverable 1: Raw I/Q data saved to %s\n', rawFilename);
    
    % 4. Baseline FM Demodulation (Deliverable 2) - MEMORY SAFE VERSION
    disp('Demodulating FM signal to audio in chunks...');
    audioFs = 48000; % Standard audio sample rate
    
    fmDemod = comm.FMBroadcastDemodulator(...
        'SampleRate', Fs, ...
        'AudioSampleRate', audioFs, ...
        'PlaySound', false); 
    
    % Pre-allocate the final audio array to save memory
    totalAudioSamples = audioFs * captureDuration;
    audioSignal = zeros(totalAudioSamples, 1);
    
    % Process the data in 0.1-second chunks
    samplesPerChunk = Fs * 0.1;
    numChunks = length(rawIQ) / samplesPerChunk;
    audioIdx = 1;
    
    for k = 1:numChunks
        % Define the start and end of the current chunk
        startIdx = (k-1)*samplesPerChunk + 1;
        endIdx = k*samplesPerChunk;
        
        % Demodulate just this small chunk
        audioChunk = fmDemod(rawIQ(startIdx:endIdx));
        
        % Place the resulting audio into our main array
        chunkLen = length(audioChunk);
        audioSignal(audioIdx : audioIdx + chunkLen - 1) = audioChunk;
        audioIdx = audioIdx + chunkLen;
    end
    
    % ... (The chunking loop finishes here) ...
    end
    
    % --- NEW FIX: Normalize the audio to prevent clipping ---
    disp('Normalizing audio amplitude...');
    audioSignal = audioSignal / max(abs(audioSignal));
    
    % Save the normalized audio
    audioFilename = sprintf('Demodulated_Audio_%s.wav', timeStamp);
    audiowrite(audioFilename, double(audioSignal), audioFs); 
    fprintf('Deliverable 2: Demodulated audio saved to %s\n', audioFilename);
    
    % 5. Time-Domain Plot of Raw I/Q Magnitude (Deliverable 3)
    % Plotting a subset to prevent MATLAB from crashing
    numSamplesToPlot = 10000;
    timeAxis = (0:numSamplesToPlot-1) * (1/Fs);
    
    figure('Name', 'Raw I/Q Magnitude', 'NumberTitle', 'off', 'Position', [150, 150, 800, 400]);
    plot(timeAxis * 1e3, abs(rawIQ(1:numSamplesToPlot)), 'b'); % Time in milliseconds
    title(sprintf('Deliverable 3: Time-Domain Magnitude of Raw I/Q Signal (fc = %.1f MHz)', fc/1e6));
    xlabel('Time (milliseconds)');
    ylabel('Magnitude |I + jQ|');
    grid on;
    
    disp('Task 2 completed successfully.');

   %% ========================================================================
   %  TASK 3: BASEBAND LOW-PASS FILTERING (WINDOW METHOD & ANALOG PROTOTYPES)
   % ========================================================================
clear; clc; % Clear workspace to ensure data comes fresh from the file

% --- 0. Load the Raw Data ---
% This pulls rawIQ, Fs, and fc into the workspace 
filename = 'Task_2_Raw_IQ_Data_2026-03-29_09-01-06.mat';
if exist(filename, 'file')
    fprintf('Loading data from %s...\n', filename);
    load(filename); 
else
    error('File %s not found. Please ensure it is in the current folder.', filename);
end

% --- 1. Filter Specifications ---
% Isolating the 200 kHz WBFM channel (100 kHz baseband bandwidth) 
cutoff = 100e3;           
filterOrder = 100;        % FIR Order for steep roll-off
iirOrder = 12;             % IIR Order for Butterworth prototype

% --- 2. FIR Filter Design (Hamming Window Method) ---
% Using fir1 as required for the windowing assignment 
fir_coeffs = fir1(filterOrder, cutoff/(Fs/2), 'low', hann(filterOrder+1));

% --- 3. IIR Filter Design (Chebyshev II Analog Prototype) ---
% Designing an equivalent IIR filter meeting magnitude specs 
[b_iir, a_iir] = cheby2(iirOrder, 60, cutoff/(Fs/2), 'low');

% --- 4. Filtering the Data ---
% Passing the loaded rawIQ data through both filters 
disp('Applying FIR and IIR filters...');
filtered_IQ_FIR = filter(fir_coeffs, 1, rawIQ);
filtered_IQ_IIR = filter(b_iir, a_iir, rawIQ);

% --- Deliverable 3.1: Magnitude and Phase Response Plots ---
figure('Name', 'Task 3: Filter Response Comparison', 'NumberTitle', 'off');
subplot(2,1,1);
[h_fir, w] = freqz(fir_coeffs, 1, 1024, Fs);
[h_iir, ~] = freqz(b_iir, a_iir, 1024, Fs);
plot(w/1e3, abs(h_fir), 'b', 'LineWidth', 1.5); hold on;
plot(w/1e3, abs(h_iir), 'r', 'LineWidth', 1.5);
title('Deliverable 3.1: Magnitude Response (FIR vs IIR)');
ylabel('Magnitude'); xlabel('Frequency (kHz)');
legend('FIR (Hanning Window)', 'IIR (Chebyshev Type II)'); grid on;

subplot(2,1,2);
% 1. Create a logical index for the passband (0 to slightly past cutoff)
% This removes the stopband noise that causes the sawtooth jumps
passband_limit = cutoff * 1.2; 
pb_idx = w <= passband_limit;

% 2. Plot unwrapped phase for FIR (Linear Phase)
plot(w(pb_idx)/1e3, unwrap(angle(h_fir(pb_idx))), 'b', 'LineWidth', 1.5); 
hold on;

% 3. Plot unwrapped phase for IIR (Non-linear Phase)
plot(w(pb_idx)/1e3, unwrap(angle(h_iir(pb_idx))), 'r', 'LineWidth', 1.5);

title('Phase Response: Comparison of Phase Linearity (Passband Focus)');
ylabel('Phase (radians)'); 
xlabel('Frequency (kHz)');
legend('FIR (Linear Phase)', 'IIR (Non-linear Phase)'); 
grid on;

% --- Deliverable 3.2: Comparative Spectrograms ---
% Visualizing a 50ms slice of the complex baseband signal
figure('Name', 'Task 3: Spectrogram Analysis', 'NumberTitle', 'off');
sliceSize = min(length(rawIQ), round(Fs * 0.05));

subplot(3,1,1);
spectrogram(rawIQ(1:sliceSize), 512, 256, 512, Fs, 'centered', 'yaxis');
title('(a) Centered but Unfiltered');

subplot(3,1,2);
spectrogram(filtered_IQ_FIR(1:sliceSize), 512, 256, 512, Fs, 'centered', 'yaxis');
title('(b) Isolated via Hamming FIR Filter');

subplot(3,1,3);
spectrogram(filtered_IQ_IIR(1:sliceSize), 512, 256, 512, Fs, 'centered', 'yaxis');
title('(c) Isolated via Butterworth IIR Filter');

fprintf('\nTask 3 completed. Ready for Technical Discussion.\n');

%% ========================================================================
%  TASK 4: OPTIMAL DENOISING VIA WIENER FILTERING
% ========================================================================
disp('Starting Task 4: Wiener Filter Denoising...');

% --- 1. Demodulation (Bridging Task 3 to Task 4) ---
% We use the FIR-filtered output because of its linear phase integrity
audioFs = 48000; 
fmDemod = comm.FMBroadcastDemodulator(...
    'SampleRate', Fs, ...
    'AudioSampleRate', audioFs, ...
    'PlaySound', false);

% This signal contains the "hiss" we want to remove
audio_noisy = fmDemod(filtered_IQ_FIR); 

% --- 2. Noise Floor Estimation (Pnn) ---
% We take a 100ms slice (assuming silence or background hiss)
noise_slice = audio_noisy(1:round(audioFs * 0.1)); 
[Pnn, f_vec] = pwelch(noise_slice, 1024, 512, 1024, audioFs);

% --- 3. Total Signal Power Estimation (Pyy) ---
[Pyy, ~] = pwelch(audio_noisy, 1024, 512, 1024, audioFs);

% --- 4. Construct Wiener Transfer Function H(f) ---
% H(f) = Pss / (Pss + Pnn) -> Where Pss = Pyy - Pnn
Pss = max(0, Pyy - Pnn); % Ensuring no negative power estimates
H_wiener = Pss ./ (Pss + Pnn + eps); 

% --- 5. Apply Filtering in Frequency Domain ---
L = length(audio_noisy);
audio_fft = fft(audio_noisy);
f_full = (0:L-1)*(audioFs/L);

% Interpolate our calculated H(f) to match the length of the audio signal
H_interp = interp1(f_vec, H_wiener, f_full, 'linear', 'extrap');
% Maintain conjugate symmetry for real-valued audio reconstruction
H_interp(f_full > audioFs/2) = fliplr(H_interp(f_full < audioFs/2 & f_full > 0));

% Apply filter and transform back to time domain
denoised_audio = real(ifft(audio_fft .* H_interp'));

% Normalize to prevent audio clipping
denoised_audio = denoised_audio / max(abs(denoised_audio));

% --- Deliverable 4.1: Power Spectrum Comparison ---
figure('Name', 'Task 4: Wiener Denoising Analysis', 'NumberTitle', 'off');
[P_after, f_after] = pwelch(denoised_audio, 1024, 512, 1024, audioFs);
plot(f_after/1e3, 10*log10(Pyy), 'r', 'LineWidth', 1, 'DisplayName', 'Pre-Wiener (LPF only)'); 
hold on;
plot(f_after/1e3, 10*log10(P_after), 'b', 'LineWidth', 1, 'DisplayName', 'Post-Wiener Denoised');
title('Deliverable 4.1: Power Spectrum Comparison (Denoising Efficiency)');
xlabel('Frequency (kHz)'); ylabel('PSD (dB/Hz)');
legend; grid on;

% --- Deliverable 4.2: Save Denoised Audio ---
output_filename = 'Denoised_FM_Audio_Task4.wav';
audiowrite(output_filename, denoised_audio, audioFs);
fprintf('Deliverable 4.2: Denoised audio saved as %s\n', output_filename);
disp('Task 4 complete. Ready for Subjective Analysis.');

%% ========================================================================
%  TASK 5: TIME-FREQUENCY ANALYSIS (STFT)
% ========================================================================
disp('Starting Task 5: STFT Analysis...');

% Parameters for STFT
winLen = 1024;
overlap = 512;
nfft = 1024;

% --- 1. Load Original Audio ---
% To satisfy the requirement for the "original" signal, we load the audio from Task 2.
% Based on your Task 3 code, your timestamp is: 2026-03-29_09-01-06
origAudioFile = 'Task_2_IQ_Demod_Init_2026-03-29_09-01-06.wav';
hasOriginal = isfile(origAudioFile);
if hasOriginal
    [audio_original, ~] = audioread(origAudioFile);
else
    disp('Warning: Task 2 audio file not found. Only plotting Filtered and Denoised STFTs.');
end

% --- Deliverable 5.1: STFT Spectrograms ---
figure('Name', 'Task 5: Time-Frequency Evolution', 'NumberTitle', 'off', 'Position', [100, 50, 800, 700]);

if hasOriginal
    % (a) Original Demodulated Signal (No LPF, contains adjacent station interference)
    subplot(3,1,1);
    stft(audio_original, audioFs, 'Window', hamming(winLen), 'OverlapLength', overlap, 'FFTLength', nfft);
    title('STFT: Original Demodulated Signal (Pre-LPF)');
    ylim([0 20]); % Focus on audible range
    
    sub_filtered = 2;
    sub_denoised = 3;
    plot_rows = 3;
else
    sub_filtered = 1;
    sub_denoised = 2;
    plot_rows = 2;
end

% (b) LPF Filtered Signal (Pre-Wiener, adjacent stations gone but "hiss" remains)
subplot(plot_rows, 1, sub_filtered);
stft(audio_noisy, audioFs, 'Window', hamming(winLen), 'OverlapLength', overlap, 'FFTLength', nfft);
title('STFT: Filtered Signal (After LPF Isolation)');
ylim([0 20]);

% (c) Wiener Denoised Signal (Hiss Suppressed)
subplot(plot_rows, 1, sub_denoised);
stft(denoised_audio, audioFs, 'Window', hamming(winLen), 'OverlapLength', overlap, 'FFTLength', nfft);
title('STFT: Denoised Signal (After Wiener Filtering)');
ylim([0 20]);

% --- Deliverable 5.2: Comparative Waveform Plots ---
figure('Name', 'Task 5: Waveform Detail', 'NumberTitle', 'off', 'Position', [150, 100, 800, 500]);
t = (0:length(audio_noisy)-1)/audioFs;

% Zoom in on a small 50ms segment to clearly see the noise reduction
t_start = 1.0; 
t_end = 1.05;

subplot(2,1,1);
plot(t, audio_noisy, 'r');
title('Waveform: Filtered Signal (Pre-Wiener)');
ylabel('Amplitude'); xlim([t_start t_end]); grid on;

subplot(2,1,2);
plot(t, denoised_audio, 'b');
title('Waveform: Denoised Signal (Post-Wiener)');
ylabel('Amplitude'); xlabel('Time (s)'); xlim([t_start t_end]); grid on;

disp('Task 5 STFT Analysis Complete.');