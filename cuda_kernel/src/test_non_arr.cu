#include <iomanip>
#include <iostream>
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
    __host__ __device__ __forceinline__ T operator()(const T & a, const T & b) const = delete;
};


template <>
struct ScanOp<float>
{
    __host__ __device__ __forceinline__ float operator()(const float & a, const float & b) const
    {
        return a + b;
    }
};


template <>
struct ScanOp<int>
{
    __host__ __device__ __forceinline__ int operator()(const int & a, const int & b) const
    {
        return a + b;
    }
};


template <typename T, typename ScanOp>
struct BlockPrefixCallbackOp
{
    __host__ __device__ BlockPrefixCallbackOp()
    {

    }

    __host__ __device__ T operator()(T blockAggregate)
    {
        T oldPrefix = runningPrefix;
        runningPrefix = scanOp(runningPrefix, blockAggregate);
        return oldPrefix;
    }

    T runningPrefix = 0;
    ScanOp scanOp;
};


template <int kMatrixX, int kMatrixY, int kBlockX, int kBlockY, int kBlockZ, int kSegLen, typename T>
__global__ void scan(const T * __restrict__ src, T * __restrict__ dst)
{
    constexpr int kWarpThreads = 32;

    using Scan = mamband::SegBlockScan<T, kSegLen, kBlockX, mamband::BLOCK_SCAN_WARP_SCANS, kBlockY, kBlockZ>;
    __shared__ typename Scan::TempStorage tempStorage;
    Scan scan(tempStorage);

    ScanOp<T> scanOp;
    using BlockPrefixCallbackOp = BlockPrefixCallbackOp<T, ScanOp<T>>;

    const int tid = threadIdx.y * kBlockX + threadIdx.x;

    const int linearWarpId = tid / kWarpThreads;
    const int warpIdx = linearWarpId % (kBlockX / kSegLen);
    const int warpIdy = linearWarpId / (kBlockX / kSegLen);

    const int linearLaneId = cub::LaneId();
    const int laneIdx = linearLaneId % kSegLen;
    const int laneIdy = linearLaneId / kSegLen;

    BlockPrefixCallbackOp yCallback[kMatrixX / kBlockX];

    #pragma unroll
    for (int yi = 0; yi < kMatrixY / kBlockY; ++yi)
    {
        BlockPrefixCallbackOp xCallback;

        #pragma unroll
        for (int xi = 0; xi < kMatrixX / kBlockX; ++xi)
        {
            const int gx = (xi * kBlockX) + (warpIdx * kSegLen + laneIdx);
            const int gy = (yi * kBlockY) + (warpIdy * (kWarpThreads / kSegLen) + laneIdy);
            const int gi = gy * kMatrixX + gx;

            T input = src[gi];
            scan.InclusiveScan(input, input, scanOp, xCallback, mamband::kHorizontal);
            scan.InclusiveScan(input, input, scanOp, yCallback[xi], mamband::kVertical);
            dst[gi] = input;
        }
    }

//    T input = src[gi];
//    scan.InclusiveScan(input, input, scanOp, blockPrefixCallbackOp, mamband::kHorizontal);
//
//    input = src[gi];
//    scan.InclusiveScan(input, input, scanOp, blockPrefixCallbackOp, mamband::kHorizontal);
//
//    scan.InclusiveScan(input, input, scanOp, blockPrefixCallbackOp, mamband::kVertical);
//    input = src[gi];
//    scan.InclusiveScan(input, input, scanOp, blockPrefixCallbackOp, mamband::kVertical);
//
//    dst[gi] = input;
}


int main()
{
    constexpr dim3 kBlock(16, 16);
    constexpr dim3 kMatrixSize(32, 32);
    constexpr bool kRandInput = true;

    using T = float;
    std::vector<T> matBuf(kMatrixSize.x * kMatrixSize.y, 1);

    if constexpr (kRandInput)
    {
        auto seed = std::random_device()();
        auto e = std::default_random_engine(seed);
        auto d = std::normal_distribution<float>(0.0f, 1.0f);
//        auto d = std::uniform_int_distribution(1, 1000000);
        auto g = [&d, &e]()
        {
            return d(e);
        };
        std::generate(matBuf.begin(), matBuf.end(), g);
    }

    thrust::host_vector<T> hostScanSrc = matBuf;

    thrust::device_vector<T> devScanSrc = hostScanSrc;
    thrust::device_vector<T> devScanDst(kMatrixSize.x * kMatrixSize.y, 0.0f);
    thrust::device_vector<T> devHoriAgg(kMatrixSize.x * kMatrixSize.y, 0.0f);
    thrust::device_vector<T> devVertAgg(kMatrixSize.x * kMatrixSize.y, 0.0f);

    scan<kMatrixSize.x, kMatrixSize.y, kBlock.x, kBlock.y, kBlock.z, kBlock.y, T><<<1, kBlock>>>(
            thrust::raw_pointer_cast(devScanSrc.data()),
            thrust::raw_pointer_cast(devScanDst.data())
    );
    CUDA_CHECK_LAST_ERROR();
    CUDA_CHECK(cudaDeviceSynchronize());

    thrust::host_vector<T> hostScanDst = devScanDst;

    auto mat = [kMatrixSize, &matBuf](int i, int j) mutable -> T &
    {
        return matBuf[i * kMatrixSize.x + j];
    };

    auto hRes = [kMatrixSize, &hostScanDst](int i, int j) mutable -> T &
    {
        return hostScanDst[i * kMatrixSize.x + j];
    };

    for (int j = 1; j < kMatrixSize.x; ++j)
    {
        mat(0, j) += mat(0, j - 1);
    }

    for (int i = 1; i < kMatrixSize.y; ++i)
    {
        mat(i, 0) += mat(i - 1, 0);
    }

    for (int i = 1; i < kMatrixSize.y; ++i)
    {
        for (int j = 1; j < kMatrixSize.x; ++j)
        {
            mat(i, j) += mat(i, j - 1) + mat(i - 1, j) - mat(i - 1, j - 1);
        }
    }

    bool isCorrect = true;
    for (int i = 0; i < kMatrixSize.y; ++i)
    {
        for (int j = 0; j < kMatrixSize.x; ++j)
        {
            if (1e-4f < std::abs(mat(i, j) - hRes(i, j)))
            {
                isCorrect = false;
            }
        }
    }
    printf("%s\n", isCorrect ? "Correct" : "WRONG!!!");

    printf("cpu\n");
    for (int i = 0; i < kMatrixSize.y; ++i)
    {
        for (int j = 0; j < kMatrixSize.x; ++j)
        {
            printf("%13.6f ", mat(i, j));
        }
        printf("\n");
    }
    printf("\n");

    printf("scan\n");
    for (int i = 0; i < kMatrixSize.y; ++i)
    {
        for (int j = 0; j < kMatrixSize.x; ++j)
        {
            printf("%13.6f ", hRes(i, j));
        }
        printf("\n");
    }
    printf("\n");

    return 0;
}
