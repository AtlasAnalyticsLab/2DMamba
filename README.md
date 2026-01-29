# 2DMamba: Efficient State Space Model for Image Representation with Applications on Giga-Pixel Whole Slide Image Classification
Pytorch implementation for the 2DMamba framework described in the paper [2DMamba: Efficient State Space Model for Image Representation with Applications on Giga-Pixel Whole Slide Image Classification](https://openaccess.thecvf.com/content/CVPR2025/html/Zhang_2DMamba_Efficient_State_Space_Model_for_Image_Representation_with_Applications_CVPR_2025_paper.html), [arxiv](https://arxiv.org/abs/2412.00678) and [poster](misc/poster.pdf).  

<div>
  <img src="misc/overview_github.jpg" width="100%"  alt="The overview of our framework."/>
</div>

## TODO
1. Adding training/testing instructions.
2. Fix bugs in draw_heatmap.py.
3. Upload model weights.
4. Pack CUDA kernel into a python package.

## Installation
Install [Anaconda/miniconda](https://www.anaconda.com/products/distribution).  
Required packages:
```
  $ conda create --name 2dmamba python=3.10
  $ conda activate 2dmamba
  $ conda install pytorch==2.2.0 torchvision==0.17.0 torchaudio==2.2.0 pytorch-cuda=11.8 -c pytorch -c nvidia
  $ conda install cuda -c nvidia/label/cuda-11.8.0
  $ conda install cmake # If you already have cmake, ignore this
  $ pip install pandas opencv-contrib-python kornia gpustat albumentations triton timm==0.4.12 tqdm pytest chardet yacs termcolor submitit tensorboardX fvcore seaborn einops tensorboard joblib
  $	pip install mamba-ssm
  $ pip install --force-reinstall -v "numpy==1.26.4"
  $ pip install mmengine==0.10.1 mmcv==2.1.0 opencv-python-headless ftfy regex
  $ pip install mmdet==3.3.0 mmsegmentation==1.2.2 mmpretrain==1.2.0

``` 
Note that because of some dependency issue of cuda packages, you may need to reinstall some/all cuda packages by:
```
# If you got an error of missing some header files
conda install nvidia/label/cuda-11.8.0::cuda-cudart-dev # For missing "cuda_runtime.h"
conda install nvidia/label/cuda-11.8.0::cuda-cupti # for missing "cuda_stdint.h"
conda install nvidia/label/cuda-11.8.0::libcusparse-dev # for missing "cusparse.h"
conda install nvidia/label/cuda-11.8.0::libcublas-dev # for missing "cublas_v2.h" or "cublas.h"

# If you want to reinstall all cuda packages
conda install cuda cuda-cccl cuda-command-line-tools cuda-compiler cuda-cudart cuda-cudart-dev cuda-cuobjdump cuda-cupti cuda-cuxxfilt cuda-demo-suite cuda-documentation cuda-driver-dev cuda-gdb cuda-libraries cuda-libraries-dev cuda-memcheck cuda-nsight cuda-nsight-compute cuda-nvcc cuda-nvdisasm cuda-nvml-dev cuda-nvprof cuda-nvprune cuda-nvrtc cuda-nvrtc-dev cuda-nvtx cuda-nvvp cuda-profiler-api cuda-runtime cuda-sanitizer-api cuda-toolkit cuda-tools cuda-version cuda-visual-tools -c nvidia/label/cuda-11.8.0
conda install libcublas libcublas-dev libcufft libcufft-dev libcufile libcufile-dev libcurand libcurand-dev libcusolver libcusolver-dev libcusparse libcusparse-dev -c nvidia/label/cuda-11.8.0
```
You can also use docker or singularity. We provide the [Dockerfile](Dockerfile) we used in our experiments. You can also pull our image on dockerhub, which should be identical to our environment, by:
```
  $ docker pull skykiny/mamba # For docker
  $ singularity pull docker://skykiny/mamba:latest # For singularity
``` 
## Build 2DMamba CUDA kernel
We use CMake to build our CUDA kernel. Please replace the ```-DPython_ROOT_DIR="/opt/conda"``` in ```cuda_kernel/build.sh``` with your python root directory. E.g. if you use conda environment and your python is located at ```/home/jzhang/Dev/anaconda3_2023/envs/vmamba/bin/python```, you should set ```-DPython_ROOT_DIR="/home/jzhang/Dev/anaconda3_2023/envs/vmamba"```. Then run ```bash build.sh```, the compiled pscan.so should appear under ```v2dmamba_scan``` folder. You can try cd to the root directory of this project and run ```import v2dmamba_scan``` in python to verify if it is correct.

## Contact
If you have any questions or concerns, feel free to report an issue or directly contact us at Jingwei Zhang <jingwezhang@cs.stonybrook.edu>, Xi Han <xihan1@cs.stonybrook.edu> and Anh Tien Nguyen <tienanhnguyen9991@gmail.com>. 

## Acknowledgments
Our framework is based on [Mamba](https://github.com/state-spaces/mamba), [VMamba](https://github.com/MzeroMiko/VMamba) and [mamba.py](https://github.com/alxndrTL/mamba.py). Thanks for their outstanding code.
The computational pathology experiments reported in this paper were executed on Korea University servers administered by Professor Jin Tae Kwak.
## Citation
If you use the code or results in your research, please use the following BibTeX entry.  
```
@InProceedings{Zhang_2025_CVPR,
    author    = {Zhang, Jingwei and Nguyen, Anh Tien and Han, Xi and Trinh, Vincent Quoc-Huy and Qin, Hong and Samaras, Dimitris and Hosseini, Mahdi S.},
    title     = {2DMamba: Efficient State Space Model for Image Representation with Applications on Giga-Pixel Whole Slide Image Classification},
    booktitle = {Proceedings of the Computer Vision and Pattern Recognition Conference (CVPR)},
    month     = {June},
    year      = {2025},
    pages     = {3583-3592}
}
```
