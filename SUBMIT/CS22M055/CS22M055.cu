/*
 * Title: CS6023, GPU Programming, Jan-May 2023, Assignment-3
 * Description: Activation Game 
 */

#include <cstdio>        // Added for printf() function 
#include <sys/time.h>    // Added to get time of day
#include <cuda.h>
#include <bits/stdc++.h>
#include <fstream>
#include "graph.hpp"
 
using namespace std;


ofstream outfile; // The handle for printing the output

/******************************Write your kerenels here ************************************/


//Kernel to calculate the end of node of a give level in a graph.
__global__ void find_level_start_end(int* d_offset, int* d_csrList, int s, int e, int *d_max_node) {
  int id = s + blockIdx.x * blockDim.x + threadIdx.x;
  if (id <= e) {
      if(d_csrList[d_offset[id + 1] - 1] > *d_max_node)
          atomicMax(&d_max_node[0] , d_csrList[d_offset[id + 1] - 1]);
          
  } 
}

//kernel to calculate the active indegree of each level except level 0.

__global__ void find_active_indegree(int* d_an, int* d_aid, int s, int e, int* d_offset, int* d_csrList) {
  int id = s + blockIdx.x * blockDim.x + threadIdx.x;
  if (id <= e) {
    if (d_an[id] == 1) {
        for (int i = d_offset[id]; i < d_offset[id + 1]; i++) {
            atomicAdd(&d_aid[d_csrList[i]],1);
        }
    }
  }
}
     
//kernel to calculate the active node for each level.  
__global__ void find_active_node(int *d_an,int *d_aid,int *d_apr, int s, int e) {
  int id =s + blockIdx.x * blockDim.x + threadIdx.x;
  if (id <= e) {
      if (d_aid[id] >= d_apr[id] ) {
          d_an[id] = 1;
      }
  }
}

//find deactive node from following active node.
__global__ void  find_deactivate_node(int *d_an, int s, int e ){
  int id =s + blockIdx.x * blockDim.x + threadIdx.x + 1;
  if (id < e) {
      if (d_an[id] == 1 && d_an[id - 1] == 0 && d_an[id + 1] == 0) {
          d_an[id] = 0;
      }
  }
}

//kernel to calculate the number of active nodes at each level.
__global__ void active_node_count(int *d_activeVertex, int *d_an, int s, int e, int level) {
  int id = s + blockIdx.x * blockDim.x + threadIdx.x;
  if (id <= e) {
      if (d_an[id] == 1) {
          atomicAdd(&d_activeVertex[level],1);
      }
  }
}
    
    
    
    
/**************************************END*************************************************/



//Function to write result in output file
void printResult(int *arr, int V,  char* filename){
    outfile.open(filename);
    for(long int i = 0; i < V; i++){
        outfile<<arr[i]<<" ";   
    }
    outfile.close();
}

/**
 * Timing functions taken from the matrix multiplication source code
 * rtclock - Returns the time of the day 
 * printtime - Prints the time taken for computation 
 **/
double rtclock(){
    struct timezone Tzp;
    struct timeval Tp;
    int stat;
    stat = gettimeofday(&Tp, &Tzp);
    if (stat != 0) printf("Error return from gettimeofday: %d", stat);
    return(Tp.tv_sec + Tp.tv_usec * 1.0e-6);
}

void printtime(const char *str, double starttime, double endtime){
    printf("%s%3f seconds\n", str, endtime - starttime);
}

int main(int argc,char **argv){
    // Variable declarations
    int V ; // Number of vertices in the graph
    int E; // Number of edges in the graph
    int L; // number of levels in the graph

    //Reading input graph
    char *inputFilePath = argv[1];
    graph g(inputFilePath);

    //Parsing the graph to create csr list
    g.parseGraph();

    //Reading graph info 
    V = g.num_nodes();
    E = g.num_edges();
    L = g.get_level();


    //Variable for CSR format on host
    int *h_offset; // for csr offset
    int *h_csrList; // for csr
    int *h_apr; // active point requirement

    //reading csr
    h_offset = g.get_offset();
    h_csrList = g.get_csr();   
    h_apr = g.get_aprArray();
    
    // Variables for CSR on device
    int *d_offset;
    int *d_csrList;
    int *d_apr; //activation point requirement array
    int *d_aid; // acive in-degree array
    //Allocating memory on device 
    cudaMalloc(&d_offset, (V+1)*sizeof(int));
    cudaMalloc(&d_csrList, E*sizeof(int)); 
    cudaMalloc(&d_apr, V*sizeof(int)); 
    cudaMalloc(&d_aid, V*sizeof(int));

    //copy the csr offset, csrlist and apr array to device
    cudaMemcpy(d_offset, h_offset, (V+1)*sizeof(int), cudaMemcpyHostToDevice);
    cudaMemcpy(d_csrList, h_csrList, E*sizeof(int), cudaMemcpyHostToDevice);
    cudaMemcpy(d_apr, h_apr, V*sizeof(int), cudaMemcpyHostToDevice);

    // variable for result, storing number of active vertices at each level, on host
    int *h_activeVertex;
    h_activeVertex = (int*)malloc(L*sizeof(int));
    // setting initially all to zero
    memset(h_activeVertex, 0, L*sizeof(int));

    // variable for result, storing number of active vertices at each level, on device
    // int *d_activeVertex;
	// cudaMalloc(&d_activeVertex, L*sizeof(int));


/***Important***/

// Initialize d_aid array to zero for each vertex
// Make sure to use comments

/***END***/
double starttime = rtclock(); 

/*********************************CODE AREA*****************************************/



  int i = 0;
  int *h_level;  //It use to represent the starting and ending index of level.
  int *d_max_node,*h_max_node;//it use to store the last node of given level.
  h_level = (int*)malloc(L * 2 * sizeof(int));
  memset(h_level, 0 , L * 2 * sizeof(int));
  cudaMalloc(&d_max_node, sizeof(int));
  h_max_node = (int*)malloc(sizeof(int));
  h_level[0] = 0;
  int j = 0;
  while (h_apr[j] == 0) {
      j++;
  }
  h_level[1] = j - 1;
  //kernel call for level calcuation.
  for (int i = 0; i < 2 * (L - 1); i = i + 2) {
      cudaMemset(d_max_node, 0, sizeof(int));
      //kerenl call.
      int gridl = ceil((float)(h_level[i+1] - h_level[i] + 1) / 1024);
      dim3 grid(gridl, 1, 1);
      find_level_start_end << < grid, 1024 >> > (d_offset,d_csrList,h_level[i],h_level[i+1],d_max_node);

      cudaMemcpy(h_max_node, d_max_node, sizeof(int), cudaMemcpyDeviceToHost);
      h_level[i+2] = h_level[i+1]+1;
      h_level[i+3] = *h_max_node;
  }



  int *h_active_node,*d_an;//Index represent the node and value represent the active node if 1 or inactive node if 0.
  int *h_active_indegree;//Store the active indegree of node.

  h_active_node = (int*)malloc(V * sizeof(int));
  h_active_indegree = (int*)malloc(V * sizeof(int));

  cudaMalloc(&d_an, sizeof(int) * V);

  memset(h_active_node, 0, V * sizeof(int));
  memset(h_active_indegree, 0, V * sizeof(int));
  
  //first level all nodes are active.
  i = 0;
  while (i <= h_level[1]) {
      h_active_node[i] = 1;
      i++;
  }

  cudaMemcpy(d_an, h_active_node, sizeof(int) * V, cudaMemcpyHostToDevice);
  cudaMemcpy(d_aid, h_active_indegree, sizeof(int) * V, cudaMemcpyHostToDevice);
  i = 0;
  while (i < 2*(L - 1)) {

      //Kernel call to find the active in degree of nodes in level i.
      int gridx=ceil((float)(h_level[i + 1] - h_level[i] + 1) / 1024);
      dim3 grid1(gridx,1,1);
      find_active_indegree << < grid1 , 1024 >> > (d_an, d_aid, h_level[i], h_level[i + 1], d_offset, d_csrList);
      cudaDeviceSynchronize();

      //kernel call to find the active node in level i+1.
      gridx=ceil((float)(h_level[i + 3] - h_level[i + 2] + 1) / 1024);
      dim3 grid2(gridx,1,1);
      find_active_node << < grid2 , 1024 >> > (d_an, d_aid, d_apr, h_level[i + 2], h_level[i + 3]);
      cudaDeviceSynchronize();

      //kernel call to find dective node in level i+1
      gridx=ceil((float)(h_level[i + 3] - h_level[i + 2] + 1) / 1024);
      dim3 grid3(gridx,1,1);
      find_deactivate_node<<<grid3,1024>>>(d_an, h_level[i + 2], h_level[i + 3]);
      cudaDeviceSynchronize();
      i = i + 2;
  }
  
  //compute count of active node at each level.
  int* d_activeVertex;
  cudaMalloc(&d_activeVertex, L*sizeof(int));
  cudaMemset(d_activeVertex, 0, L * sizeof(int));
  for (int i = 0; i < 2*L; i=i+2) {
      //kernel calling.
      int gridx=ceil((float)(h_level[i + 1] - h_level[i] + 1) / 1024);
      dim3 grid3(gridx,1,1);
      active_node_count << < grid3 , 1024 >> > (d_activeVertex, d_an, h_level[i], h_level[i + 1],i/2);
  }
  cudaMemcpy(h_activeVertex, d_activeVertex, sizeof(int) * L, cudaMemcpyDeviceToHost);

  //deallocate cudamemory
  cudaFree(d_an);
  cudaFree(d_max_node);

  //deallocate memory
  free(h_level);
  free(h_max_node);
  free(h_active_indegree);
  free(h_active_node);

/********************************END OF CODE AREA**********************************/
double endtime = rtclock();  
printtime("GPU Kernel time: ", starttime, endtime);  

// --> Copy C from Device to Host
char outFIle[30] = "./output.txt" ;
printResult(h_activeVertex, L, outFIle);
if(argc>2)
{
    for(int i=0; i<L; i++)
    {
        printf("level = %d , active nodes = %d\n",i,h_activeVertex[i]);
    }
}

    return 0;
}
