/******************************************************************************
 * Copyright (c) 2023, Tri Dao.
 ******************************************************************************/

// Split into multiple files to compile in paralell

#include "selective_scan/selective_scan_fwd_kernel.cuh"


template void selective_scan_fwd_cuda<float, float, float>(SSMParamsBase & params, cudaStream_t stream);
