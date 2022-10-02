#include <bits/stdc++.h>
#include <stdio.h>
#include <stdlib.h>
#include <thrust/binary_search.h>
#include <thrust/device_vector.h>
#include <thrust/execution_policy.h>
#include <thrust/functional.h>
#include <thrust/sort.h>
#include <time.h>

#include <algorithm>
#include <ctime>
#include <fstream>
#include <map>
#include <math.h>
#include <set>
#include <vector>

using namespace std;

#define RANGE 2
#define UNPROCESSED -1
#define NOISE -2

#define DIMENSION 2
#define TREE_LEVELS (DIMENSION + 1)

#define THREAD_BLOCKS 256
#define THREAD_COUNT 256

#define MAX_SEEDS 1024

__managed__ int MINPTS = 4;
__managed__ double EPS = 1.5;
__managed__ int DATASET_COUNT = 400000;
__managed__ int PARTITION_SIZE = 80;

#define POINTS_SEARCHED 9

#define PORTO 1
#define SPATIAL 0
#define NGSI 0
#define IONO2D 0
#define SPATIAL3D 0
#define IONO3D 0

struct __align__(8) IndexStructure {
  int dimension;
  int dataBegin;
  int dataEnd;
  int childFrom;
};

/**
**************************************************************************
//////////////////////////////////////////////////////////////////////////
* GPU ERROR function checks for potential erros in cuda function execution
//////////////////////////////////////////////////////////////////////////
**************************************************************************
*/
#define gpuErrchk(ans) \
  { gpuAssert((ans), __FILE__, __LINE__); }
inline void gpuAssert(cudaError_t code, const char *file, int line,
                      bool abort = true) {
  if (code != cudaSuccess) {
    fprintf(stderr, "GPUassert: %s %s %d\n", cudaGetErrorString(code), file,
            line);
    if (abort) exit(code);
  }
}

/**
**************************************************************************
//////////////////////////////////////////////////////////////////////////
* Declare CPU and GPU Functions
//////////////////////////////////////////////////////////////////////////
**************************************************************************
*/
int ImportDataset(char const *fname, double *dataset);

bool MonitorSeedPoints(vector<int>& unprocessedPoints, int* runningCluster,
                       int* d_cluster, int* d_seedList, int* d_seedLength,
                       int* d_collisionMatrix, int* d_results);

void GetDbscanResult(int* d_cluster, int* runningCluster, int* clusterCount,
                     int* noiseCount);

__global__ void DBSCAN(double* dataset, int* cluster, int* seedList,
                       int* seedLength, int* collisionMatrix,
                       int* results,
                       struct IndexStructure** indexBuckets,
                       int* indexesStack, int* dataValue, double* upperBounds,
                       double* binWidth, double *minPoints, double *maxPoints);

__device__ void MarkAsCandidate(int neighborID, int chainID, int* cluster,
                                int* seedList, int* seedLength, int* collisionMatrix);

                                __global__ void INDEXING_ADJUSTMENT(int *indexTreeMetaData,
                                    struct IndexStructure **indexBuckets,
                                    int *dataKey);

__global__ void INDEXING_STRUCTURE(double *dataset, int *indexTreeMetaData,
                                        double *minPoints, double *maxPoints,
                                        double *binWidth, int *results,
                                        struct IndexStructure **indexBuckets,
                                        int *dataKey, int *dataValue,
                                        double *upperBounds);

__device__ void insertData(int id, double *dataset,
                                struct IndexStructure **indexBuckets,
                                int *dataKey, int *dataValue,
                                double *upperBounds, double *binWidth,
                                double *minPoints, double *maxPoints);

__device__ void indexConstruction(int level, int *indexTreeMetaData,
                                       double *minPoints, double *binWidth,
                                       struct IndexStructure **indexBuckets,
                                       double *upperBounds);

__device__ void searchPoints(double *data, int chainID, double *dataset,
                                  int *results,
                                  struct IndexStructure **indexBuckets,
                                  int *indexesStack, int *dataValue,
                                  double *upperBounds, double *binWidth,
                                  double *minPoints, double *maxPoints);



void runDBSCAN(const char* filename, int datasetSize, double eps, int minPts, int partition) {

  EPS = eps;
  MINPTS = minPts;
  DATASET_COUNT = datasetSize;
  PARTITION_SIZE = partition;


  printf("Using dataset file %s\n", filename);
  double *importedDataset =
      (double *)malloc(sizeof(double) * DATASET_COUNT * DIMENSION);

  // Import data from dataset
  int ret = ImportDataset(filename, importedDataset);
  if (ret == 1) {
    printf("\nError importing the dataset");
    return;
  }

  // Get the total count of dataset
  vector<int> unprocessedPoints;
  for (int x = 0; x < DATASET_COUNT; x++) {
    unprocessedPoints.push_back(x);
  }

  // Reset the GPU device for potential memory issues
  gpuErrchk(cudaDeviceReset());
  gpuErrchk(cudaFree(0));

  // Start the time
  clock_t totalTimeStart, totalTimeStop, indexingStart, indexingStop;
  float totalTime = 0.0;
  float indexingTime = 0.0;
  totalTimeStart = clock();

  /**
 **************************************************************************
 * CUDA Memory allocation
 **************************************************************************
 */

  double *d_dataset;
  int *d_cluster;
  int *d_seedList;
  int *d_seedLength;
  int *d_collisionMatrix;

  gpuErrchk(cudaMalloc((void **)&d_dataset,
                       sizeof(double) * DATASET_COUNT * DIMENSION));

  gpuErrchk(cudaMalloc((void **)&d_cluster, sizeof(int) * DATASET_COUNT));

  gpuErrchk(cudaMalloc((void **)&d_seedList,
                       sizeof(int) * THREAD_BLOCKS * MAX_SEEDS));

  gpuErrchk(cudaMalloc((void **)&d_seedLength, sizeof(int) * THREAD_BLOCKS));

  gpuErrchk(cudaMalloc((void **)&d_collisionMatrix,
                       sizeof(int) * THREAD_BLOCKS * THREAD_BLOCKS));


  /**
 **************************************************************************
 * Indexing Memory allocation
 **************************************************************************
 */

  indexingStart = clock();

  int *d_indexTreeMetaData;
  int *d_results;
  double *d_minPoints;
  double *d_maxPoints;
  double *d_binWidth;

  gpuErrchk(cudaMalloc((void **)&d_indexTreeMetaData,
                       sizeof(int) * TREE_LEVELS * RANGE));

  gpuErrchk(cudaMalloc((void **)&d_results,
                       sizeof(int) * THREAD_BLOCKS * POINTS_SEARCHED));

  gpuErrchk(cudaMalloc((void **)&d_minPoints, sizeof(double) * DIMENSION));
  gpuErrchk(cudaMalloc((void **)&d_maxPoints, sizeof(double) * DIMENSION));

  gpuErrchk(cudaMalloc((void **)&d_binWidth, sizeof(double) * DIMENSION));

  gpuErrchk(
      cudaMemset(d_results, -1, sizeof(int) * THREAD_BLOCKS * POINTS_SEARCHED));

  /**
 **************************************************************************
 * Assignment with default values
 **************************************************************************
 */
  gpuErrchk(cudaMemcpy(d_dataset, importedDataset,
                       sizeof(double) * DATASET_COUNT * DIMENSION,
                       cudaMemcpyHostToDevice));

  gpuErrchk(cudaMemset(d_cluster, UNPROCESSED, sizeof(int) * DATASET_COUNT));

  gpuErrchk(
      cudaMemset(d_seedList, -1, sizeof(int) * THREAD_BLOCKS * MAX_SEEDS));

  gpuErrchk(cudaMemset(d_seedLength, 0, sizeof(int) * THREAD_BLOCKS));

  gpuErrchk(cudaMemset(d_collisionMatrix, -1,
                       sizeof(int) * THREAD_BLOCKS * THREAD_BLOCKS));

  /**
**************************************************************************
* Initialize index structure
**************************************************************************
*/
  double maxPoints[DIMENSION];
  double minPoints[DIMENSION];

  for (int j = 0; j < DIMENSION; j++) {
    maxPoints[j] = 0;
    minPoints[j] = 999999999;
  }

  for (int i = 0; i < DATASET_COUNT; i++) {
    for (int j = 0; j < DIMENSION; j++) {
      if (importedDataset[i * DIMENSION + j] > maxPoints[j]) {
        maxPoints[j] = importedDataset[i * DIMENSION + j];
      }
      if (importedDataset[i * DIMENSION + j] < minPoints[j]) {
        minPoints[j] = importedDataset[i * DIMENSION + j];
      }
    }
  }

  double binWidth[DIMENSION];
  double minBinSize = 99999999;
  for (int x = 0; x < DIMENSION; x++) {
    binWidth[x] = (double)(maxPoints[x] - minPoints[x]) / PARTITION_SIZE;
    if (minBinSize >= binWidth[x]) {
      minBinSize = binWidth[x];
    }
  }

  if (minBinSize < EPS) {
    printf("Bin width (%f) is less than EPS(%f).\n", minBinSize, EPS);
    exit(0);
  }

  // Level Partition
  int treeLevelPartition[TREE_LEVELS] = {1};

  for (int i = 0; i < DIMENSION; i++) {
    treeLevelPartition[i + 1] = PARTITION_SIZE;
  }

  int childItems[TREE_LEVELS];
  int startEndIndexes[TREE_LEVELS * RANGE];

  int mulx = 1;
  for (int k = 0; k < TREE_LEVELS; k++) {
    mulx *= treeLevelPartition[k];
    childItems[k] = mulx;
  }

  for (int i = 0; i < TREE_LEVELS; i++) {
    if (i == 0) {
      startEndIndexes[i * RANGE + 0] = 0;
      startEndIndexes[i * RANGE + 1] = 1;
      continue;
    }
    startEndIndexes[i * RANGE + 0] = startEndIndexes[((i - 1) * RANGE) + 1];
    startEndIndexes[i * RANGE + 1] = startEndIndexes[i * RANGE + 0];
    for (int k = 0; k < childItems[i - 1]; k++) {
      startEndIndexes[i * RANGE + 1] += treeLevelPartition[i];
    }
  }

  gpuErrchk(cudaMemcpy(d_minPoints, minPoints, sizeof(double) * DIMENSION,
                       cudaMemcpyHostToDevice));
  gpuErrchk(cudaMemcpy(d_maxPoints, maxPoints, sizeof(double) * DIMENSION,
  cudaMemcpyHostToDevice));
  gpuErrchk(cudaMemcpy(d_binWidth, binWidth, sizeof(double) * DIMENSION,
                       cudaMemcpyHostToDevice));

  gpuErrchk(cudaMemcpy(d_indexTreeMetaData, startEndIndexes,
                       sizeof(int) * TREE_LEVELS * RANGE,
                       cudaMemcpyHostToDevice));

  int indexedStructureSize = startEndIndexes[DIMENSION * RANGE + 1];

  // Allocate memory for index buckets
  struct IndexStructure **d_indexBuckets, *d_currentIndexBucket;

  gpuErrchk(cudaMalloc((void **)&d_indexBuckets,
                       sizeof(struct IndexStructure *) * indexedStructureSize));

  for (int i = 0; i < indexedStructureSize; i++) {
    gpuErrchk(cudaMalloc((void **)&d_currentIndexBucket,
                         sizeof(struct IndexStructure)));
    gpuErrchk(cudaMemcpy(&d_indexBuckets[i], &d_currentIndexBucket,
                         sizeof(struct IndexStructure *),
                         cudaMemcpyHostToDevice));
  }

  // Allocate memory for current indexes stack
  int indexBucketSize = 1;
  for (int i = 0; i < DIMENSION; i++) {
    indexBucketSize *= 3;
  }

  indexBucketSize = indexBucketSize * THREAD_BLOCKS;

  int *d_indexesStack;

  gpuErrchk(
      cudaMalloc((void **)&d_indexesStack, sizeof(int) * indexBucketSize));

  cudaFree(d_currentIndexBucket);

  /**
 **************************************************************************
 * Data key-value pair
 **************************************************************************
 */
  int *d_dataKey;
  int *d_dataValue;
  double *d_upperBounds;

  gpuErrchk(cudaMalloc((void **)&d_dataKey, sizeof(int) * DATASET_COUNT));
  gpuErrchk(cudaMalloc((void **)&d_dataValue, sizeof(int) * DATASET_COUNT));
  gpuErrchk(cudaMalloc((void **)&d_upperBounds,
                       sizeof(double) * indexedStructureSize));
  /**
 **************************************************************************
 * Start Indexing first
 **************************************************************************
 */

 
  cudaDeviceSetLimit(cudaLimitMallocHeapSize, 16*1024*1024);
  gpuErrchk(cudaDeviceSynchronize());

  INDEXING_STRUCTURE<<<dim3(THREAD_BLOCKS, 1), dim3(THREAD_COUNT, 1)>>>(
      d_dataset, d_indexTreeMetaData, d_minPoints, d_maxPoints, d_binWidth, d_results,
      d_indexBuckets, d_dataKey, d_dataValue, d_upperBounds);
  gpuErrchk(cudaDeviceSynchronize());

  cudaFree(d_indexTreeMetaData);
  

  /**
 **************************************************************************
 * Sorting and adjusting Data key-value pair
 **************************************************************************
 */

  thrust::sort_by_key(thrust::device, d_dataKey, d_dataKey + DATASET_COUNT,
                      d_dataValue);

  gpuErrchk(cudaDeviceSynchronize());

  INDEXING_ADJUSTMENT<<<dim3(THREAD_BLOCKS, 1), dim3(THREAD_COUNT, 1)>>>(
      d_indexTreeMetaData, d_indexBuckets, d_dataKey);

  gpuErrchk(cudaDeviceSynchronize());

  indexingStop = clock();

  /**
 **************************************************************************
 * Start the DBSCAN algorithm
 **************************************************************************
 */

  // Keep track of number of cluster formed without global merge
  int runningCluster = THREAD_BLOCKS;
  // Global cluster count
  int clusterCount = 0;

  // Keeps track of number of noises
  int noiseCount = 0;

  // Handler to conmtrol the while loop
  bool exit = false;

  clock_t communicationStart, communicationStop, dbscanKernelStart, dbscanKernelStop;
  float communicationTime = 0.0;
  float dbscanKernelTime = 0.0;

  while (!exit) {

    communicationStart = clock();
    // Monitor the seed list and return the comptetion status of points
    int completed =
        MonitorSeedPoints(unprocessedPoints, &runningCluster,
                          d_cluster, d_seedList, d_seedLength,
                          d_collisionMatrix, d_results);

    communicationStop = clock();
    communicationTime += (float)(communicationStop - communicationStart) / CLOCKS_PER_SEC;

    // If all points are processed, exit
    if (completed) {
      exit = true;
    }

    if (exit) break;

    dbscanKernelStart = clock();

    // Kernel function to expand the seed list
    gpuErrchk(cudaDeviceSynchronize());
    DBSCAN<<<dim3(THREAD_BLOCKS, 1), dim3(THREAD_COUNT, 1)>>>(
        d_dataset, d_cluster, d_seedList, d_seedLength, d_collisionMatrix,
        d_results, d_indexBuckets, d_indexesStack,
        d_dataValue, d_upperBounds, d_binWidth, d_minPoints, d_maxPoints);
    gpuErrchk(cudaDeviceSynchronize());

    dbscanKernelStop = clock();
    dbscanKernelTime += (float)(dbscanKernelStop - dbscanKernelStart) / CLOCKS_PER_SEC;
  }

  /**
 **************************************************************************
 * End DBSCAN and show the results
 **************************************************************************
 */
  totalTimeStop = clock();
  
  // Get the DBSCAN result
  GetDbscanResult(d_cluster, &runningCluster, &clusterCount, &noiseCount);
  
  totalTime = (float)(totalTimeStop - totalTimeStart) / CLOCKS_PER_SEC;
  indexingTime = (float)(indexingStop - indexingStart) / CLOCKS_PER_SEC;

  printf("==============================================\n");
  printf("Dataset: %d\nEPS: %f\nMINPTS: %d\nPARTITION: %d\n", DATASET_COUNT, EPS, MINPTS, PARTITION_SIZE);
  printf("Final cluster after merging: %d\n", clusterCount);
  printf("Number of noises: %d\n", noiseCount);
  printf("Indexing Time: %3.2f seconds\n", indexingTime);
  printf("Communication Time: %3.2f seconds\n", communicationTime);
  printf("DBSCAN kernel Time: %3.2f seconds\n", dbscanKernelTime);
  printf("Total Time: %3.2f seconds\n", totalTime);
  printf("==============================================\n");

  /**
 **************************************************************************
 * Free CUDA memory allocations
 **************************************************************************
 */

  cudaFree(d_dataset);
  cudaFree(d_cluster);
  cudaFree(d_seedList);
  cudaFree(d_seedLength);
  cudaFree(d_collisionMatrix);

  cudaFree(d_results);
  cudaFree(d_indexBuckets);
  cudaFree(d_indexesStack);

  cudaFree(d_dataKey);
  cudaFree(d_dataValue);
  cudaFree(d_upperBounds);
  cudaFree(d_binWidth);

  cudaFree(d_minPoints);
  cudaFree(d_maxPoints);
}


__global__ void DBSCAN(double *dataset, int *cluster, int *seedList,
                       int *seedLength, int *collisionMatrix,
                      int *results,
                       struct IndexStructure **indexBuckets,
                       int *indexesStack, int *dataValue, double *upperBounds,
                       double *binWidth, double *minPoints, double *maxPoints) {
  // Point ID to expand by a block
  __shared__ int pointID;

  // Neighbors to store of neighbors points exceeds minpoints
  __shared__ int neighborBuffer[64];

  // It counts the total neighbors
  __shared__ int neighborCount;

  // ChainID is basically blockID
  __shared__ int chainID;

  // Store the point from pointID
  __shared__ double point[DIMENSION];

  // Length of the seedlist to check its size
  __shared__ int currentSeedLength;

  __shared__ int resultId;

  if (threadIdx.x == 0) {
    chainID = blockIdx.x;
    currentSeedLength = seedLength[chainID];
    pointID = seedList[chainID * MAX_SEEDS + currentSeedLength - 1];
  }
  __syncthreads();


    // Check if the point is already processed
    if (threadIdx.x == 0) {
      seedLength[chainID] = currentSeedLength - 1;
      neighborCount = 0;
      for (int x = 0; x < DIMENSION; x++) {
        point[x] = dataset[pointID * DIMENSION + x];
      }
    }
    __syncthreads();

    ///////////////////////////////////////////////////////////////////////////////////

    searchPoints(point, chainID, dataset, results, indexBuckets, indexesStack,
                 dataValue, upperBounds, binWidth, minPoints, maxPoints);

    __syncthreads();

    for (int k = 0; k < POINTS_SEARCHED; k++) {
      if (threadIdx.x == 0) {
        resultId = results[chainID * POINTS_SEARCHED + k];
      }
      __syncthreads();

      if (resultId == -1) break;

      for (int i = threadIdx.x + indexBuckets[resultId]->dataBegin;
           i < indexBuckets[resultId]->dataEnd; i = i + THREAD_COUNT) {
        register double comparingPoint[DIMENSION];

        for (int x = 0; x < DIMENSION; x++) {
          comparingPoint[x] = dataset[dataValue[i] * DIMENSION + x];
        }

        register double distance = 0;
        for (int x = 0; x < DIMENSION; x++) {
          distance +=
              (point[x] - comparingPoint[x]) * (point[x] - comparingPoint[x]);
        }

        if (distance <= EPS * EPS) {
          register int currentNeighborCount = atomicAdd(&neighborCount, 1);
          if (currentNeighborCount >= MINPTS) {
            MarkAsCandidate(dataValue[i], chainID, cluster, seedList,
                            seedLength, collisionMatrix);
          } else {
            neighborBuffer[currentNeighborCount] = dataValue[i];
          }
        }
      }
      __syncthreads();
    }
    __syncthreads();

    ///////////////////////////////////////////////////////////////////////////////////

    if (neighborCount >= MINPTS) {
      cluster[pointID] = chainID;
      for (int i = threadIdx.x; i < MINPTS; i = i + THREAD_COUNT) {
        MarkAsCandidate(neighborBuffer[i], chainID, cluster, seedList,
                        seedLength, collisionMatrix);
      }
    } else {
      cluster[pointID] = NOISE;
    }

    __syncthreads();
    ///////////////////////////////////////////////////////////////////////////////////

    if (threadIdx.x == 0 && seedLength[chainID] >= MAX_SEEDS) {
      seedLength[chainID] = MAX_SEEDS - 1;
    }
    __syncthreads();
  
}

bool MonitorSeedPoints(vector<int> &unprocessedPoints, int *runningCluster,
                       int *d_cluster, int *d_seedList, int *d_seedLength,
                       int *d_collisionMatrix,
                       int *d_results) {
  int *localSeedLength;
  localSeedLength = (int *)malloc(sizeof(int) * THREAD_BLOCKS);
  gpuErrchk(cudaMemcpy(localSeedLength, d_seedLength,
                       sizeof(int) * THREAD_BLOCKS, cudaMemcpyDeviceToHost));

  int *localSeedList;
  localSeedList = (int *)malloc(sizeof(int) * THREAD_BLOCKS * MAX_SEEDS);
  gpuErrchk(cudaMemcpy(localSeedList, d_seedList,
                       sizeof(int) * THREAD_BLOCKS * MAX_SEEDS,
                       cudaMemcpyDeviceToHost));

  int *localCollisionMatrix;
  localCollisionMatrix =
      (int *)malloc(sizeof(int) * THREAD_BLOCKS * THREAD_BLOCKS);
  gpuErrchk(cudaMemcpy(localCollisionMatrix, d_collisionMatrix,
                       sizeof(int) * THREAD_BLOCKS * THREAD_BLOCKS,
                       cudaMemcpyDeviceToHost));

  gpuErrchk(
      cudaMemset(d_results, -1, sizeof(int) * THREAD_BLOCKS * POINTS_SEARCHED));

  int completeSeedListFirst = false;
  for (int i = 0; i < THREAD_BLOCKS; i++) {
    if (localSeedLength[i] > 0) {
      completeSeedListFirst = true;
    }
  }
  if (completeSeedListFirst) {
    free(localSeedList);
    free(localSeedLength);
    return false;
  }
  ////////////////////////////////////////////////////////////////////////////////////////

  int clusterMap[THREAD_BLOCKS];
  set<int> blockSet;
  for (int i = 0; i < THREAD_BLOCKS; i++) {
    blockSet.insert(i);
  }

  set<int>::iterator it;

  while (blockSet.empty() == 0) {
    it = blockSet.begin();
    int curBlock = *it;
    set<int> expansionQueue;
    set<int> finalQueue;

    expansionQueue.insert(curBlock);
    finalQueue.insert(curBlock);

    while (expansionQueue.empty() == 0) {
      it = expansionQueue.begin();
      int expandBlock = *it;
      expansionQueue.erase(it);
      blockSet.erase(expandBlock);
      for (int x = 0; x < THREAD_BLOCKS; x++) {
        if (x == expandBlock) continue;
        if (localCollisionMatrix[expandBlock * THREAD_BLOCKS + x] == 1 &&
            blockSet.find(x) != blockSet.end()) {
          expansionQueue.insert(x);
          finalQueue.insert(x);
        }
      }
    }

    for (it = finalQueue.begin(); it != finalQueue.end(); ++it) {
      clusterMap[*it] = curBlock;
    }
  }

  int clusterCountMap[THREAD_BLOCKS];
  for (int x = 0; x < THREAD_BLOCKS; x++) {
    clusterCountMap[x] = UNPROCESSED;
  }

  for (int x = 0; x < THREAD_BLOCKS; x++) {
    if (clusterCountMap[clusterMap[x]] != UNPROCESSED) continue;
    clusterCountMap[clusterMap[x]] = (*runningCluster);
    (*runningCluster)++;
  }

  for (int x = 0; x < THREAD_BLOCKS; x++) {
    thrust::replace(thrust::device, d_cluster, d_cluster + DATASET_COUNT, x,
                    clusterCountMap[clusterMap[x]]);
  }

  //////////////////////////////////////////////////////////////////////////////////////////

  int *localCluster;
  localCluster = (int *)malloc(sizeof(int) * DATASET_COUNT);
  gpuErrchk(cudaMemcpy(localCluster, d_cluster, sizeof(int) * DATASET_COUNT,
                       cudaMemcpyDeviceToHost));

  int complete = 0;
  for (int i = 0; i < THREAD_BLOCKS; i++) {
    bool found = false;
    while (!unprocessedPoints.empty()) {
      int lastPoint = unprocessedPoints.back();
      unprocessedPoints.pop_back();

      if (localCluster[lastPoint] == UNPROCESSED) {
        localSeedLength[i] = 1;
        localSeedList[i * MAX_SEEDS] = lastPoint;
        found = true;
        break;
      }
    }

    if (!found) {
      complete++;
    }
  }

  // FInally, transfer back the CPU memory to GPU and run DBSCAN process

  gpuErrchk(cudaMemcpy(d_seedLength, localSeedLength,
                       sizeof(int) * THREAD_BLOCKS, cudaMemcpyHostToDevice));

  gpuErrchk(cudaMemcpy(d_seedList, localSeedList,
                       sizeof(int) * THREAD_BLOCKS * MAX_SEEDS,
                       cudaMemcpyHostToDevice));

  gpuErrchk(cudaMemset(d_collisionMatrix, -1,
                       sizeof(int) * THREAD_BLOCKS * THREAD_BLOCKS));

  // Free CPU memories

  free(localCluster);
  free(localSeedList);
  free(localSeedLength);
  free(localCollisionMatrix);

  if (complete == THREAD_BLOCKS) {
    return true;
  }

  return false;
}

__device__ void MarkAsCandidate(int neighborID, int chainID, int *cluster,
                                int *seedList, int *seedLength,
                                int *collisionMatrix) {
  register int oldState =
      atomicCAS(&(cluster[neighborID]), UNPROCESSED, chainID);

  if (oldState == UNPROCESSED) {
    register int sl = atomicAdd(&(seedLength[chainID]), 1);
    if (sl < MAX_SEEDS) {
      seedList[chainID * MAX_SEEDS + sl] = neighborID;
    }
  }
 else if (oldState != NOISE && oldState != chainID &&
           oldState < THREAD_BLOCKS) {
    collisionMatrix[oldState * THREAD_BLOCKS + chainID] = 1;
    collisionMatrix[chainID * THREAD_BLOCKS + oldState] = 1;
  }

  else if (oldState == NOISE) {
    oldState = atomicCAS(&(cluster[neighborID]), NOISE, chainID);
  }
}

void GetDbscanResult(int *d_cluster, int *runningCluster, int *clusterCount,
                     int *noiseCount) {
  *noiseCount = thrust::count(thrust::device, d_cluster, d_cluster + DATASET_COUNT, NOISE);
  int *d_localCluster;
  gpuErrchk(cudaMalloc((void **)&d_localCluster, sizeof(int) * DATASET_COUNT));
  thrust::copy(thrust::device, d_cluster, d_cluster + DATASET_COUNT, d_localCluster);
  thrust::sort(thrust::device, d_localCluster, d_localCluster + DATASET_COUNT);
  *clusterCount = thrust::unique(thrust::device, d_localCluster, d_localCluster + DATASET_COUNT) - d_localCluster - 1;
  


  int *localCluster;
  localCluster = (int *)malloc(sizeof(int) * DATASET_COUNT);
  gpuErrchk(cudaMemcpy(localCluster, d_localCluster, sizeof(int) * DATASET_COUNT,
                        cudaMemcpyDeviceToHost));
  ofstream outputFile;
  outputFile.open("./out/cuda_dclust_extended.txt");
  for (int j = 0; j < DATASET_COUNT; j++) {
    outputFile << localCluster[j] << endl;
  }
  outputFile.close();
  free(localCluster);


  cudaFree(d_localCluster);
}

__device__ void searchPoints(double *data, int chainID, double *dataset,
                                  int *results,
                                  struct IndexStructure **indexBuckets,
                                  int *indexesStack, int *dataValue,
                                  double *upperBounds, double *binWidth, double *minPoints, double *maxPoints) {

  __shared__ int resultsCount;
  __shared__ int indexBucketSize;
  __shared__ int currentIndex;
  __shared__ int currentIndexSize;
  __shared__ double comparingData;

  if (threadIdx.x == 0) {
    resultsCount = 0;
    indexBucketSize = 1;
    for (int i = 0; i < DIMENSION; i++) {
      indexBucketSize *= 3;
    }
    indexBucketSize = indexBucketSize * chainID;
    currentIndexSize = indexBucketSize;
    indexesStack[currentIndexSize++] = 0;
  }
  __syncthreads();

  while (currentIndexSize > indexBucketSize) {
    if (threadIdx.x == 0) {
      currentIndexSize = currentIndexSize - 1;
      currentIndex = indexesStack[currentIndexSize];
      comparingData = data[indexBuckets[currentIndex]->dimension];
    }
    __syncthreads();

    for (int k = threadIdx.x + indexBuckets[currentIndex]->childFrom;
         k < indexBuckets[currentIndex]->childFrom + PARTITION_SIZE;
         k = k + THREAD_COUNT) {
      double leftRange;
      double rightRange;
      if (k == indexBuckets[currentIndex]->childFrom) {
        leftRange =
            upperBounds[k] - binWidth[indexBuckets[currentIndex]->dimension];
      } else {
        leftRange = upperBounds[k - 1];
      }

      rightRange = upperBounds[k];

      if (comparingData >= leftRange && comparingData < rightRange) {
        if (indexBuckets[currentIndex]->dimension == DIMENSION - 1) {
          int oldResultsCount = atomicAdd(&resultsCount, 1);
          results[chainID * POINTS_SEARCHED + oldResultsCount] = k;

          if (k > indexBuckets[currentIndex]->childFrom) {
            oldResultsCount = atomicAdd(&resultsCount, 1);
            results[chainID * POINTS_SEARCHED + oldResultsCount] = k - 1;
          }

          if (k < indexBuckets[currentIndex]->childFrom + PARTITION_SIZE - 1) {
            oldResultsCount = atomicAdd(&resultsCount, 1);
            results[chainID * POINTS_SEARCHED + oldResultsCount] = k + 1;
          }
        } else {
          int oldCurrentIndexSize = atomicAdd(&currentIndexSize, 1);
          indexesStack[oldCurrentIndexSize] = k;
          if (k > indexBuckets[currentIndex]->childFrom) {
            int oldCurrentIndexSize = atomicAdd(&currentIndexSize, 1);
            indexesStack[oldCurrentIndexSize] = k - 1;
          }
          if (k < indexBuckets[currentIndex]->childFrom + PARTITION_SIZE - 1) {
            int oldCurrentIndexSize = atomicAdd(&currentIndexSize, 1);
            indexesStack[oldCurrentIndexSize] = k + 1;
          }
        }
      }
    }

    __syncthreads();
  }
}



__device__ void indexConstruction(int level, int *indexTreeMetaData,
                                  double *minPoints, double *binWidth,
                                  struct IndexStructure **indexBuckets,
                                  double *upperBounds) {
  for (int k = threadIdx.x + indexTreeMetaData[level * RANGE + 0];
       k < indexTreeMetaData[level * RANGE + 1]; k = k + THREAD_COUNT) {
    for (int i = 0; i < PARTITION_SIZE; i++) {
      int currentBucketIndex =
          indexTreeMetaData[level * RANGE + 1] + i +
          (k - indexTreeMetaData[level * RANGE + 0]) * PARTITION_SIZE;

      indexBuckets[k]->dimension = level;
      indexBuckets[currentBucketIndex]->dimension = level + 1;

      if (i == 0) {
        indexBuckets[k]->childFrom = currentBucketIndex;
      }

      double rightPoint =
          minPoints[level] + i * binWidth[level] + binWidth[level];

      if (i == PARTITION_SIZE - 1) rightPoint = rightPoint + binWidth[level];

      upperBounds[currentBucketIndex] = rightPoint;
    }
  }
  __syncthreads();
}

__device__ void insertData(int id, double *dataset,
                           struct IndexStructure **indexBuckets, int *dataKey,
                           int *dataValue, double *upperBounds,
                           double *binWidth, double *minPoints, double *maxPoints) {
  int index = 0;
  for (int j = 0; j < DIMENSION; j++) {
    double x = dataset[id * DIMENSION + j];
    int currentIndex = (x - minPoints[j]) / (maxPoints[j] - minPoints[j]) * PARTITION_SIZE + 1;
    index = index * PARTITION_SIZE + currentIndex;
  }

  dataValue[id] = id;
  dataKey[id] = index;
}


__global__ void INDEXING_ADJUSTMENT(int *indexTreeMetaData,
                                    struct IndexStructure **indexBuckets,
                                    int *dataKey) {
  __shared__ int indexingRange;
  if (threadIdx.x == 0) {
    indexingRange = indexTreeMetaData[DIMENSION * RANGE + 1] -
                    indexTreeMetaData[DIMENSION * RANGE];
  }
  __syncthreads();

  int threadId = blockDim.x * blockIdx.x + threadIdx.x;

  for (int i = threadId; i < indexingRange;
       i = i + THREAD_COUNT * THREAD_BLOCKS) {
    int idx = indexTreeMetaData[DIMENSION * RANGE] + i;

    thrust::pair<int *, int *> dataPositioned;

    dataPositioned = thrust::equal_range(thrust::device, dataKey, dataKey + DATASET_COUNT, idx);

    indexBuckets[idx]->dataBegin = dataPositioned.first - dataKey;
    indexBuckets[idx]->dataEnd = dataPositioned.second - dataKey;
  }
  __syncthreads();
}


__global__ void INDEXING_STRUCTURE(double *dataset, int *indexTreeMetaData,
                                   double *minPoints, double *maxPoints, double *binWidth,
                                   int *results,
                                   struct IndexStructure **indexBuckets,
                                   int *dataKey, int *dataValue,
                                   double *upperBounds) {
  if (blockIdx.x < DIMENSION) {
    indexConstruction(blockIdx.x, indexTreeMetaData, minPoints, binWidth,
                      indexBuckets, upperBounds);
  }
  __syncthreads();

  int threadId = blockDim.x * blockIdx.x + threadIdx.x;
  for (int i = threadId; i < DATASET_COUNT;
       i = i + THREAD_COUNT * THREAD_BLOCKS) {
    insertData(i, dataset, indexBuckets, dataKey, dataValue, upperBounds,
               binWidth, minPoints, maxPoints);
  }
  __syncthreads();
}


/**
**************************************************************************
//////////////////////////////////////////////////////////////////////////
* Import Dataset
* It imports the data from the file and store in dataset variable
//////////////////////////////////////////////////////////////////////////
**************************************************************************
*/
int ImportDataset(char const *fname, double *dataset) {
  FILE *fp = fopen(fname, "r");
  if (!fp) {
    printf("Unable to open file\n");
    return (1);
  }

  char buf[4096];
  unsigned long int cnt = 0;
  while (fgets(buf, 4096, fp) && cnt < DATASET_COUNT * DIMENSION) {
    char *field = strtok(buf, ",");
    long double tmp;
    sscanf(field, "%Lf", &tmp);
    dataset[cnt] = tmp;
    cnt++;

    while (field) {
      field = strtok(NULL, ",");

      if (field != NULL) {
        long double tmp;
        sscanf(field, "%Lf", &tmp);
        dataset[cnt] = tmp;
        cnt++;
      }
    }
  }
  fclose(fp);
  return 0;
}


/**
**************************************************************************
//////////////////////////////////////////////////////////////////////////
* Main CPU function
//////////////////////////////////////////////////////////////////////////
**************************************************************************
*/

int main() {

 // Generate random datasets
 char *datasetPath;
  double setOfR[5];
  int setOfMinPts[5];
  int defaultMin, defaultPts;
  double defaultR;
  int defaultP;
  int setOfDataSize[5];
  int setOfP[5];

  if (PORTO) {
    setOfDataSize[0] = 40000;
    setOfDataSize[1] = 80000;
    setOfDataSize[2] = 160000;
    setOfDataSize[3] = 320000;
    setOfDataSize[4] = 640000;

    setOfR[0] = 0.002;
    setOfR[1] = 0.004;
    setOfR[2] = 0.006;
    setOfR[3] = 0.008;
    setOfR[4] = 0.01;

    setOfMinPts[0] = 4;
    setOfMinPts[1] = 8;
    setOfMinPts[2] = 16;
    setOfMinPts[3] = 32;
    setOfMinPts[4] = 64;

    defaultMin = 8;
    defaultR = 0.008;
    defaultPts = 160000;

    defaultP = 30;
    datasetPath = "/data/dbscan/Porto_taxi_data.csv";
  }

  if (NGSI) {
    setOfDataSize[0] = 50000;
    setOfDataSize[1] = 100000;
    setOfDataSize[2] = 200000;
    setOfDataSize[3] = 400000;
    setOfDataSize[4] = 800000;

    setOfR[0] = 0.5;
		setOfR[1] = 0.75;
		setOfR[2] = 1;
		setOfR[3] = 1.25;
		setOfR[4] = 1.5;

    setOfMinPts[0] = 4;
    setOfMinPts[1] = 8;
    setOfMinPts[2] = 16;
    setOfMinPts[3] = 32;
    setOfMinPts[4] = 64;

    defaultMin = 8;
    defaultR = 1.25;
    defaultPts = 400000;

    defaultP = 100;
    datasetPath = "/home/mpoudel/datasets/NGSIM_Data.txt";
  }

  if (SPATIAL) {
    setOfDataSize[0] = 25000;
    setOfDataSize[1] = 50000;
    setOfDataSize[2] = 100000;
    setOfDataSize[3] = 200000;
    setOfDataSize[4] = 400000;

    setOfR[0] = 0.002;
    setOfR[1] = 0.004;
    setOfR[2] = 0.006;
    setOfR[3] = 0.008;
    setOfR[4] = 0.01;

    setOfMinPts[0] = 4;
    setOfMinPts[1] = 8;
    setOfMinPts[2] = 16;
    setOfMinPts[3] = 32;
    setOfMinPts[4] = 64;

    defaultMin = 8;
    defaultR = 0.008;
    defaultPts = 400000;

    defaultP = 80;
    datasetPath = "/home/mpoudel/datasets/3D_spatial_network.csv";
  }

  if (IONO2D) {
    setOfDataSize[0] = 50000;
    setOfDataSize[1] = 100000;
    setOfDataSize[2] = 200000;
    setOfDataSize[3] = 400000;
    setOfDataSize[4] = 800000;

    setOfR[0] = 0.5;
    setOfR[1] = 0.75;
    setOfR[2] = 1;
    setOfR[3] = 1.25;
    setOfR[4] = 1.5;

    setOfMinPts[0] = 4;
    setOfMinPts[1] = 8;
    setOfMinPts[2] = 16;
    setOfMinPts[3] = 32;
    setOfMinPts[4] = 64;

    defaultMin = 4;
    defaultR = 1.5;
    defaultPts = 400000;

    defaultP = 80;
    datasetPath = "/data/geodata/iono_20min_2Mpts_2D.txt";
  }

  if (SPATIAL3D) {
    setOfDataSize[0] = 25000;
    setOfDataSize[1] = 50000;
    setOfDataSize[2] = 100000;
    setOfDataSize[3] = 200000;
    setOfDataSize[4] = 400000;

    setOfR[0] = 0.02;
    setOfR[1] = 0.04;
    setOfR[2] = 0.06;
    setOfR[3] = 0.08;
    setOfR[4] = 0.1;

    setOfMinPts[0] = 1;
    setOfMinPts[1] = 2;
    setOfMinPts[2] = 4;
    setOfMinPts[3] = 8;
    setOfMinPts[4] = 16;

    defaultMin = 2;
    defaultR = 0.08;
    defaultPts = 400000;

    defaultP = 10;
    datasetPath = "/home/mpoudel/datasets/3D_spatial_network.txt";
  }

  if (IONO3D) {
    setOfDataSize[0] = 100000;
    setOfDataSize[1] = 200000;
    setOfDataSize[2] = 400000;
    setOfDataSize[3] = 800000;
    setOfDataSize[4] = 1600000;

    setOfR[0] = 0.5;
    setOfR[1] = 0.75;
    setOfR[2] = 1;
    setOfR[3] = 1.25;
    setOfR[4] = 1.5;

    setOfMinPts[0] = 4;
    setOfMinPts[1] = 8;
    setOfMinPts[2] = 16;
    setOfMinPts[3] = 32;
    setOfMinPts[4] = 64;

    defaultMin = 4;
    defaultR = 1.5;
    defaultPts = 400000;

    defaultP = 40;
    datasetPath = "/data/geodata/iono_20min_2Mpts_3D.txt";
  }


    // // Different set of Eps
    // printf("################ EPS IMPACT ################\n");
    // for (int i = 0; i < 5; i++) {
    //   runDBSCAN(datasetPath, defaultPts, setOfR[i], defaultMin, defaultP);
    // }

    // // Different set of MinPts
    // printf("################ MINPTS IMPACT ################\n");
    // for (int i = 0; i < 5; i++) {
    //   runDBSCAN(datasetPath, defaultPts, defaultR, setOfMinPts[i], defaultP);
    // }
  
    // Different set of Points
    printf("################ POINTS IMPACT ################\n");
    for (int i = 0; i < 5; i++) {
      runDBSCAN(datasetPath, setOfDataSize[i], defaultR, defaultMin, defaultP);
    }


    // setOfP[0] = 10;
    // setOfP[1] = 20;
    // setOfP[2] = 30;
    // setOfP[3] = 40;
    // setOfP[4] = 50;
    
    // printf("################ PARTITION - POINTS IMPACT ################\n");
    // for (int i = 0; i < 5; i++) {
    //   for (int j = 0; j < 5; j++) {
    //     runDBSCAN(datasetPath, setOfDataSize[i], defaultR, defaultMin, setOfP[j]);
    //   }
    // }

    // printf("################ PARTITION - EPS IMPACT ################\n");
    // for (int i = 0; i < 5; i++) {
    //   for (int j = 0; j < 5; j++) {
    //     runDBSCAN(datasetPath, defaultPts, setOfR[i], defaultMin, setOfP[j]);
    //   }
    // }

  
}
