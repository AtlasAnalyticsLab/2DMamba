#include <numeric>
#include <random>

#include <cub/block/block_scan.cuh>
#include <cub/util_ptx.cuh>
#include <thrust/device_vector.h>
#include <thrust/host_vector.h>

#include "utils/cuda_utils.h"
#include "scan/block_scan.cuh"
#include "scan/commons.h"



template <typename T>
struct ScanOp
{
    __device__ __forceinline__ T operator()(const T & a, const T & b) = delete;
};


template <>
struct ScanOp<float>
{
    __device__ __forceinline__ float operator()(const float & a, const float & b)
    {
        return a + b;
    }
};


template <>
struct ScanOp<float2>
{
    __device__ __forceinline__ float2 operator()(const float2 & a, const float2 & b)
    {
        return {a.x + b.x, a.y + b.y};
    }
};


template <int kBlockX, int kBlockY, int kBlockZ, int kSegLen, typename T>
__global__ void scan(const T * __restrict__ src,
                     T * __restrict__ dst,
                     T * __restrict__ horiAgg,
                     T * __restrict__ vertAgg)
{
    constexpr int kWarpThreads = 32;
    constexpr int kThreadSpan = 2;

    using Scan = mamband::SegBlockScan<T, kSegLen, kBlockX, mamband::BLOCK_SCAN_WARP_SCANS, kBlockY, kBlockZ>;
    __shared__ typename Scan::TempStorage tempStorage;
    Scan scan(tempStorage);

    ScanOp<T> scanOp;

    int tid = threadIdx.y * kBlockX + threadIdx.x;

    int linearWarpId = tid / kWarpThreads;
    int warpIdx = linearWarpId % (kBlockX / kSegLen);
    int warpIdy = linearWarpId / (kBlockX / kSegLen);

    int linearLaneId = cub::LaneId();
    int laneIdx = linearLaneId % kSegLen;
    int laneIdy = linearLaneId / kSegLen;

    int gx = (warpIdx * kSegLen + laneIdx) * kThreadSpan;
    int gy = (warpIdy * (kWarpThreads / kSegLen) + laneIdy) * kThreadSpan;

    T input[kThreadSpan][kThreadSpan];

    for (int y = 0; y < kThreadSpan; ++y)
    {
        for (int x = 0; x < kThreadSpan; ++x)
        {
            const int gi = (gy + y) * kBlockX * kThreadSpan + (gx + x);
            input[y][x] = src[gi];
        }
    }

    scan.InclusiveScan(input, input, scanOp, mamband::kHorizontal);
    scan.InclusiveScan(input, input, scanOp, mamband::kVertical);

    for (int y = 0; y < kThreadSpan; ++y)
    {
        for (int x = 0; x < kThreadSpan; ++x)
        {
            const int gi = (gy + y) * kBlockX * kThreadSpan + (gx + x);
            dst[gi] = input[y][x];
        }
    }
}


int main()
{
    constexpr dim3 kBlock(16, 16);
    constexpr dim3 kMatrix(32, 32);
    constexpr bool kRandInput = false;

    std::vector<float> matBuf(kMatrix.x * kMatrix.y, 1.0f);

    if constexpr (kRandInput)
    {
        auto seed = std::random_device()();
        auto e = std::default_random_engine(seed);
        auto d = std::normal_distribution<float>(1.0f, 4.0f);
        auto g = [&d, &e]()
        {
            return d(e);
        };
        std::generate(matBuf.begin(), matBuf.end(), g);
    }

    thrust::host_vector<float> hostScanSrc = matBuf;

    thrust::device_vector<float> devScanSrc = hostScanSrc;
    thrust::device_vector<float> devScanDst(kMatrix.x * kMatrix.y, 1234567.0f);
    thrust::device_vector<float> devHoriAgg(kMatrix.x * kMatrix.y, 0.0f);
    thrust::device_vector<float> devVertAgg(kMatrix.x * kMatrix.y, 0.0f);

    scan<kBlock.x, kBlock.y, kBlock.z, kBlock.y, float><<<1, kBlock>>>(
            thrust::raw_pointer_cast(devScanSrc.data()),
            thrust::raw_pointer_cast(devScanDst.data()),
            thrust::raw_pointer_cast(devHoriAgg.data()),
            thrust::raw_pointer_cast(devVertAgg.data())
    );
    CUDA_CHECK_LAST_ERROR();
    CUDA_CHECK(cudaDeviceSynchronize());

    thrust::host_vector<float> hostScanDst = devScanDst;
    thrust::host_vector<float> hostHoriAgg = devHoriAgg;
    thrust::host_vector<float> hostVertAgg = devVertAgg;

    auto mat = [kMatrix, &matBuf](int i, int j) mutable -> float &
    {
        return matBuf.at(i * kMatrix.x + j);
    };

    auto hRes = [kMatrix, &hostScanDst](int i, int j) mutable -> float &
    {
        return hostScanDst[i * kMatrix.x + j];
    };

    for (int j = 1; j < kMatrix.x; ++j)
    {
        mat(0, j) += mat(0, j - 1);
    }

    for (int i = 1; i < kMatrix.y; ++i)
    {
        mat(i, 0) += mat(i - 1, 0);
    }

    for (int i = 1; i < kMatrix.y; ++i)
    {
        for (int j = 1; j < kMatrix.x; ++j)
        {
            mat(i, j) += mat(i, j - 1) + mat(i - 1, j) - mat(i - 1, j - 1);
        }
    }

    printf("cpu\n");
    for (int i = 0; i < kMatrix.y; ++i)
    {
        for (int j = 0; j < kMatrix.x; ++j)
        {
            printf("%3.0f ", mat(i, j));
        }
        printf("\n");
    }
    printf("\n");

    printf("scan\n");
    for (int i = 0; i < kMatrix.y; ++i)
    {
        for (int j = 0; j < kMatrix.x; ++j)
        {
            printf("%3.0f ", hRes(i, j));
        }
        printf("\n");
    }
    printf("\n");

    return 0;
}
