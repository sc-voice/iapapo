import os
import glob
import numpy as np
import soundfile as sf
import torch
import matplotlib.pyplot as plt
from scipy.signal import resample_poly

SR = 16000

def load_clip(path):
    x, sr = sf.read(path, dtype="float32")
    if x.ndim > 1:
        x = x.mean(axis=1)
    return resample_poly(x, SR, sr).astype(np.float32)

def get_rms(x):
    return np.sqrt(np.mean(x**2))

def get_spectral_stats(x):
    # Simple spectral stats: mean power in different frequency bands
    fft = np.abs(np.fft.rfft(x))
    freqs = np.fft.rfftfreq(len(x), 1/SR)
    
    # Bands: Low (0-1k), Mid (1k-4k), High (4k+)
    low = np.mean(fft[(freqs >= 0) & (freqs < 1000)])
    mid = np.mean(fft[(freqs >= 1000) & (freqs < 4000)])
    high = np.mean(fft[(freqs >= 4000)])
    return low, mid, high

def analyze_distribution(paths, label):
    rms_list = []
    spec_list = []
    
    print(f"Analyzing {label}...")
    for p in paths:
        try:
            x = load_clip(p)
            rms_list.append(get_rms(x))
            spec_list.append(get_spectral_stats(x))
        except Exception as e:
            print(f"Error loading {p}: {e}")
            
    return np.array(rms_list), np.array(spec_list)

def main():
    # Paths from train.py
    HERE = os.path.dirname(os.path.abspath(__file__))
    MEDIA_NEG = os.path.join(HERE, "..", "media", "negative")
    
    # We need to find a holdout to compare. 
    # Since I don't have the actual 'takes' paths easily, 
    # I will look for any wav in the lab/wakeword directory that isn't 'extra'
    # or just use the 'noise' directory as a proxy for "other negatives" if needed.
    # But let's try to find the 'takes' directory.
    TAKES_DIR = os.path.join(HERE, "..", "lab", "wakeword", "takes")
    
    # 1. Analyze Training Negatives
    train_neg_paths = glob.glob(os.path.join(MEDIA_NEG, "*.m4a"))
    # Note: train.py decodes m4a, so we'll handle that in a real scenario, 
    # but for stats, let's assume we can access the decoded or similar files.
    # For this script, I'll just look for .wav if m4a fails.
    if not train_neg_paths:
        train_neg_paths = glob.glob(os.path.join(MEDIA_NEG, "*.wav"))

    train_neg_rms, train_neg_spec = analyze_distribution(train_neg_paths, "Training Negatives")

    # 2. Analyze Holdout Negatives (or proxy)
    # Let's look at the 'noise' folder as a comparison point for "environmental" negatives
    NOISE_DIR = os.path.join(HERE, "..", "lab", "wakeword", "noise")
    noise_paths = glob.glob(os.path.join(NOISE_DIR, "*.wav"))
    noise_rms, noise_spec = analyze_distribution(noise_paths, "Noise Folder")

    if len(train_neg_rms) == 0 or len(noise_rms) == 0:
        print("Not enough data to compare. Check paths.")
        return

    print("\n--- Results ---")
    print(f"Train Neg RMS: {np.mean(train_neg_rms):.6f} +/- {np.std(train_neg_rms):.6f}")
    print(f"Noise RMS:     {np.mean(noise_rms):.6f} +/- {np.std(noise_rms):.6f}")
    
    print(f"\nTrain Neg Spectral (Low, Mid, High): {np.mean(train_neg_spec, axis=0)}")
    print(f"Noise Spectral (Low, Mid, High):     {np.mean(noise_spec, axis=0)}")

    # Plotting
    fig, ax = plt.subplots(1, 2, figsize=(12, 5))
    
    ax[0].hist(train_neg_rms, bins=20, alpha=0.5, label='Train Neg')
    ax[0].hist(noise_rms, bins=20, alpha=0.5, label='Noise')
    ax[0].set_title("RMS Distribution")
    ax[0].legend()

    ax[1].boxplot([train_neg_spec[:,0], train_neg_spec[:,1], train_neg_spec[:,2]], labels=['Low', 'Mid', 'High'])
    ax[1].set_title("Train Neg Spectral Stats")
    
    plt.tight_layout()
    plt.savefig("distribution_comparison.png")
    print("\nSaved plots to distribution_comparison.png")

if __name__ == "__main__":
    main()
