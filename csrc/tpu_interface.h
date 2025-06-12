#ifndef TPU_INTERFACE_H
#define TPU_INTERFACE_H

#include <stdint.h> // for int8_t

// Forward declare the QuantizedTensor struct
// to avoid circular dependencies if runq.c includes this file.
typedef struct {
    int8_t* q;    // quantized values
    float* s; // scaling factors
} QuantizedTensor;

// Define hardware accelerator dimensions.
// These MUST match the parameters in your Verilog code.
#define HW_ARRAY_SIZE 8
#define HW_K_ACCUM_DEPTH 32

/**
 * @brief Performs matrix-vector multiplication using the Verilog TPU.
 *
 * This function handles tiling the large matrices, writing tile data to files
 * for the Verilog simulation, invoking the simulator, reading back the results,
 * and correctly accumulating them.
 *
 * @param xout The floating-point output vector (size d).
 * @param x The quantized input activation vector (size n).
 * @param w The quantized input weight matrix (d x n).
 * @param n The common dimension (columns of W, rows of x).
 * @param d The output dimension (rows of W, rows of xout).
 * @param GS The group size used for quantization scaling factors.
 */
void matmul_hw(float* xout, QuantizedTensor *x, QuantizedTensor *w, int n, int d, int GS);

#endif // TPU_INTERFACE_H
