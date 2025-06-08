#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <cuda.h>
#include <time.h>

#define ALPHA 0.01
#define DX 0.02
#define DY 0.02
#define DT 0.0005
#define T 1500.0
#define BMP_HEADER_SIZE 54

__device__ double compute_point(double *grid, int i, int j, int nx, int ny, double r) {
    int idx = i * ny + j;
    return grid[idx]
           + r * (grid[(i + 1) * ny + j] + grid[(i - 1) * ny + j] - 2 * grid[idx])
           + r * (grid[i * ny + j + 1] + grid[i * ny + j - 1] - 2 * grid[idx]);
}

__global__ void heat_step(double *grid, double *new_grid, int nx, int ny, double r) {
    int j = blockIdx.x * blockDim.x + threadIdx.x;
    int i = blockIdx.y * blockDim.y + threadIdx.y;

    if (i > 0 && i < nx - 1 && j > 0 && j < ny - 1) {
        int idx = i * ny + j;
        new_grid[idx] = grid[idx]
            + r * (grid[(i + 1) * ny + j] + grid[(i - 1) * ny + j] - 2 * grid[idx])
            + r * (grid[i * ny + j + 1] + grid[i * ny + j - 1] - 2 * grid[idx]);
    }
}

void initialize_grid(double *grid, int nx, int ny) {
    for (int i = 0; i < nx; i++) {
        for (int j = 0; j < ny; j++) {
            if (i == j || i == nx - 1 - j)
                grid[i * ny + j] = T;
            else
                grid[i * ny + j] = 0.0;
        }
    }

    for (int i = 0; i < nx; i++) {
        grid[i * ny + 0] = 0.0;
        grid[i * ny + (ny - 1)] = 0.0;
    }
    for (int j = 0; j < ny; j++) {
        grid[0 * ny + j] = 0.0;
        grid[(nx - 1) * ny + j] = 0.0;
    }
}

void write_bmp_header(FILE *file, int width, int height) {
    unsigned char header[BMP_HEADER_SIZE] = {0};
    int file_size = BMP_HEADER_SIZE + 3 * width * height;
    header[0] = 'B'; header[1] = 'M';
    header[2] = file_size & 0xFF; header[3] = (file_size >> 8) & 0xFF;
    header[4] = (file_size >> 16) & 0xFF; header[5] = (file_size >> 24) & 0xFF;
    header[10] = BMP_HEADER_SIZE;
    header[14] = 40;
    header[18] = width & 0xFF; header[19] = (width >> 8) & 0xFF;
    header[22] = height & 0xFF; header[23] = (height >> 8) & 0xFF;
    header[26] = 1; header[28] = 24;
    fwrite(header, 1, BMP_HEADER_SIZE, file);
}

void get_color(double value, unsigned char *r, unsigned char *g, unsigned char *b) {
    if (value >= 500.0) { *r = 255; *g = 0; *b = 0; }
    else if (value >= 100.0) { *r = 255; *g = 128; *b = 0; }
    else if (value >= 50.0) { *r = 171; *g = 71; *b = 188; }
    else if (value >= 25.0) { *r = 255; *g = 255; *b = 0; }
    else if (value >= 1.0) { *r = 0; *g = 0; *b = 255; }
    else if (value >= 0.1) { *r = 5; *g = 248; *b = 252; }
    else { *r = 255; *g = 255; *b = 255; }
}

void write_grid(FILE *file, double *grid, int nx, int ny) {
    for (int i = nx - 1; i >= 0; i--) {
        for (int j = 0; j < ny; j++) {
            unsigned char r, g, b;
            get_color(grid[i * ny + j], &r, &g, &b);
            fwrite(&b, 1, 1, file);
            fwrite(&g, 1, 1, file);
            fwrite(&r, 1, 1, file);
        }
        for (int p = 0; p < (4 - (ny * 3) % 4) % 4; p++) fputc(0, file);
    }
}

int main(int argc, char *argv[]) {
    if (argc < 4 || argc > 6) {
        printf("Usage: %s <grid_size> <steps> <output.bmp> [BLOCK_X BLOCK_Y]\n", argv[0]);
        return 1;
    }

    int nx = atoi(argv[1]);
    int ny = nx;
    int steps = atoi(argv[2]);
    double r = ALPHA * DT / (DX * DY);

    int BLOCK_X = 16;
    int BLOCK_Y = 16;
    if (argc == 6) {
        BLOCK_X = atoi(argv[4]);
        BLOCK_Y = atoi(argv[5]);
    }

    size_t size = nx * ny * sizeof(double);
    double *h_grid = (double *)calloc(nx * ny, sizeof(double));
    double *h_result = (double *)calloc(nx * ny, sizeof(double));

    double *d_grid, *d_new_grid;
    cudaMalloc((void **)&d_grid, size);
    cudaMalloc((void **)&d_new_grid, size);

    initialize_grid(h_grid, nx, ny);
    cudaMemcpy(d_grid, h_grid, size, cudaMemcpyHostToDevice);

    dim3 blockDim(BLOCK_X, BLOCK_Y);
    dim3 gridDim((ny + BLOCK_X - 1) / BLOCK_X, (nx + BLOCK_Y - 1) / BLOCK_Y);

    cudaEvent_t start, stop;
    cudaEventCreate(&start);
    cudaEventCreate(&stop);
    cudaEventRecord(start);

    for (int t = 0; t < steps; t++) {
        heat_step<<<gridDim, blockDim>>>(d_grid, d_new_grid, nx, ny, r);
        double *tmp = d_grid;
        d_grid = d_new_grid;
        d_new_grid = tmp;
    }

    cudaEventRecord(stop);
    cudaEventSynchronize(stop);

    float milliseconds = 0;
    cudaEventElapsedTime(&milliseconds, start, stop);
    printf("Execution time: %.3f ms for grid %dx%d and %d steps\n", milliseconds, nx, ny, steps);

    cudaMemcpy(h_result, d_grid, size, cudaMemcpyDeviceToHost);

    FILE *f = fopen(argv[3], "wb");
    if (!f) {
        printf("Error opening output file.\n");
        return 1;
    }
    write_bmp_header(f, nx, ny);
    write_grid(f, h_result, nx, ny);
    fclose(f);

    free(h_grid); free(h_result);
    cudaFree(d_grid); cudaFree(d_new_grid);

    return 0;
}
