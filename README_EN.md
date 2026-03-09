# Real-Time Visual Tracking on SoC FPGA

## Problem

Robotics, surveillance, and automation systems frequently need to track objects in real time using image data. However, embedded platforms have limitations in processing power, energy consumption, and latency, which makes it difficult to execute complex computer vision algorithms using only CPU or GPU resources.

Thus, the challenge arises to develop an **efficient visual tracking system capable of operating in real time on embedded hardware**, without relying on techniques that require prior training.

---

## Solution

This project implements a visual tracking system using a **hardware/software co-design approach on a SoC FPGA**.

Visual feature extraction is accelerated in hardware using a **Histogram of Oriented Gradients (HOG)** feature descriptor, which is a computer vision technique, implemented on the FPGA. The tracking task is formulated as a **two-dimensional optimization problem**, solved by bio-inspired algorithms executed on the ARM processor.

Communication between hardware and software is performed using **AXI-Stream and DMA**, enabling efficient real-time processing.

---

## Platform

- **Kria KV260 Vision AI Starter Kit**
- **Zynq UltraScale+ MPSoC**

---

## Tools Used

### Hardware Design
- VHDL
- Vivado

### Embedded Systems
- PYNQ
- Embedded Linux

### Software
- Python
- JupyterLab

### Protocols and Integration
- AXI4
- AXI-Stream
- AXI-DMA

### Algorithms
- HOG (Histogram of Oriented Gradients)
- PSO (Particle Swarm Optimization)
- GWO (Grey Wolf Optimizer)
- Firefly Algorithm

---

## Results

Best tested configuration:

ROI: **64 × 64 pixels**

| Algorithm | FPS | IoU | CLE |
|-----------|-----|-----|-----|
| PSO | 16.30 | 0.8817 | 3.31 px |
| GWO | 17.99 | 0.8732 | 3.47 px |

The results demonstrate the **feasibility of real-time visual tracking using FPGA acceleration**, provided that the system does not require an update rate higher than the one experimentally obtained.

---

## Proposed Improvements

Some improvements can be explored to increase performance, reduce latency, and expand the applicability of the system:

**Increasing the FPGA operating frequency**  
A natural evolution of the architecture consists of increasing the accelerator operating frequency from **50 MHz to 100 MHz**, provided that timing closure can be achieved.

**Greater parallelization of the HOG pipeline**  
The architecture can be expanded to further exploit FPGA parallelism by dividing the HOG descriptor computation into more stages or replicating parts of the pipeline. This approach can increase throughput and reduce the total feature extraction time.

**Bare-metal implementation on the PS**  
Replacing the current environment with a **bare-metal implementation in C/C++** on the processor can reduce operating system overhead and improve the temporal predictability of the embedded solution.

**Adaptive stopping criteria in bio-inspired algorithms**  
Optimization algorithms can be improved with additional stopping criteria, such as:

- minimum cost threshold
- stagnation detection
- early interruption due to convergence
- stopping based on solution stability across iterations

These mechanisms can reduce the average execution time without compromising tracking quality.

**Better exploitation of software vectorization**  
Another possibility is optimizing the embedded software using additional vectorization techniques and memory organization strategies, reducing the computational cost of the stages executed on the processor.

**Reduction of the computational cost of the evaluation function**  
A promising direction consists of replacing or complementing the current cost function with metrics that are less computationally demanding and more suitable for the tracking problem. Among the possibilities, the following can be investigated:

---

## Author

Nathan Spínola Zeidan  
Electronic Engineering — University of Brasília
