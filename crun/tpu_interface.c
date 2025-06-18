#include "tpu_interface.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

/**
 * @brief 将仿真参数写入配置文件。
 * 这是C代码向Verilog仿真环境传递动态参数的关键。
 * @param filename 配置文件的名称。
 * @param k_accum_depth 要写入的累加深度值。
 */
static void write_sim_config(const char* filename, int k_accum_depth) {
    FILE *f_config = fopen(filename, "w");
    if (!f_config) {
        fprintf(stderr, "致命错误：无法创建仿真配置文件 %s\n", filename);
        exit(1);
    }
    // 将整数值写入文件，Verilog测试平台将读取此值
    fprintf(f_config, "%d\n", k_accum_depth);
    fclose(f_config);
}

/**
 * @brief (调试功能) 将完整的权重矩阵W和激活向量X写入文件。
 * @param x 输入的激活向量。
 * @param w 权重矩阵。
 * @param n 矩阵的列数（输入维度）。
 * @param d 矩阵的行数（输出维度）。
 */
static void write_full_matrices(QuantizedTensor *x, QuantizedTensor *w, int n, int d) {
    FILE *f_full_weights = fopen("full_weights.txt", "w");
    FILE *f_full_vector = fopen("full_vector.txt", "w");

    if (!f_full_weights || !f_full_vector) {
        fprintf(stderr, "错误：无法打开用于写入的完整矩阵输出文件。\n");
        if (f_full_weights) fclose(f_full_weights);
        if (f_full_vector) fclose(f_full_vector);
        return;
    }

    for (int i = 0; i < d; ++i) {
        for (int j = 0; j < n; ++j) {
            fprintf(f_full_weights, "%d ", w->q[i * n + j]);
        }
        fprintf(f_full_weights, "\n");
    }

    for (int i = 0; i < n; ++i) {
        fprintf(f_full_vector, "%d\n", x->q[i]);
    }

    fclose(f_full_weights);
    fclose(f_full_vector);
}

/**
 * @brief 将一个数据瓦片（Tile）写入文件，供Verilog测试平台读取。
 * 瓦片的宽度现在由 K_ACCUM_DEPTH_FOR_TILE (即GS) 控制。
 */
static void write_hw_input_tile(QuantizedTensor *x, QuantizedTensor *w, int mat_row_start, int mat_col_start, int n, int d, int K_ACCUM_DEPTH_FOR_TILE) {
    FILE *f_weights = fopen("weights.txt", "w");
    FILE *f_vector = fopen("vector.txt", "w");
    if (!f_weights || !f_vector) {
        fprintf(stderr, "错误：无法打开用于写入的硬件输入文件。\n");
        exit(1);
    }

    for (int i = 0; i < HW_ARRAY_SIZE; ++i) {
        for (int j = 0; j < K_ACCUM_DEPTH_FOR_TILE; ++j) {
            int row = mat_row_start + i;
            int col = mat_col_start + j;
            if (row < d && col < n) {
                fprintf(f_weights, "%02x\n", (unsigned char)w->q[row * n + col]);//打印n行的GS个元素
            } else {
                fprintf(f_weights, "00\n");
            }
        }
    }

    for (int i = 0; i < K_ACCUM_DEPTH_FOR_TILE; ++i) {
        int idx = mat_col_start + i;
        if (idx < n) {
            fprintf(f_vector, "%02x\n", (unsigned char)x->q[idx]);
        } else {
            fprintf(f_vector, "00\n");
        }
    }

    fclose(f_weights);
    fclose(f_vector);
}

/**
 * @brief 从文本文件中读取十六进制数，并存入32位有符号整数缓冲区。
 * 此函数能自动跳过注释行 (以 // 开头) 和空行。
 * @param results_buffer 指向用于存储结果的缓冲区的指针。
 */
static void read_hw_output(int32_t* results_buffer) {
    FILE *f_out = fopen("memory_dump.txt", "r");
    if (!f_out) {
        fprintf(stderr, "错误：无法打开 memory_dump.txt 文件用于读取。\n");
        exit(1);
    }

    char line_buffer[256]; // 用于存储文件中一行的缓冲区
    int i = 0;

    // 逐行读取文件，直到缓冲区满或文件结束
    while (i < HW_ARRAY_SIZE && fgets(line_buffer, sizeof(line_buffer), f_out)) {
        
        // 检查并跳过注释行 (以//开头)
        if (line_buffer[0] == '/' && line_buffer[1] == '/') {
            continue;
        }

        // 检查并跳过空行或只包含空白字符的行
        // strspn 返回字符串中第一个不在指定字符集中的字符的索引
        if (strspn(line_buffer, " \t\n\r") == strlen(line_buffer)) {
            continue;
        }

        // 尝试从当前行解析一个十六进制数
        // 注意：使用 %x 而不是 %d
        if (sscanf(line_buffer, "%x", (unsigned int*)&results_buffer[i]) == 1) {
            // 如果解析成功，则移动到缓冲区的下一个位置
            i++;
        } else {
            // 如果某一行非注释行无法解析，则打印警告
            fprintf(stderr, "警告：无法解析行内容 \"%s\"\n", line_buffer);
        }
    }

    // 如果读取到的数据少于预期，则填充剩余部分并给出警告
    if (i < HW_ARRAY_SIZE) {
        fprintf(stderr, "警告：只成功读取了 %d 个结果，预期为 %d 个。剩余部分将置为0。\n", i, HW_ARRAY_SIZE);
        for (int j = i; j < HW_ARRAY_SIZE; ++j) {
            results_buffer[j] = 0;
        }
    }

    fclose(f_out);
}


/**
 * @brief 主要的硬件卸载函数。
 * 该版本实现了动态累加深度配置和精确的反量化。
 *
 * @param xout 指向浮点输出向量的指针。
 * @param x 输入的量化激活向量。
 * @param w 量化的权重矩阵。
 * @param n 矩阵的列数（输入维度）。
 * @param d 矩阵的行数（输出维度）。
 * @param GS 量化分组大小，将被用作硬件的累加深度。
 */
void matmul_hw(float* xout, QuantizedTensor *x, QuantizedTensor *w, int n, int d, int GS) {
    // ==================== 新增的打印信息 ====================
    // 在每次调用时，打印当前矩阵乘法的维度和分组信息
    // fprintf(stderr, "\n C->HW Matmul Info:\n");
    // fprintf(stderr, "--------------------------------------------------\n");
    // fprintf(stderr, "  - Weight Matrix (W) Dimensions : %d x %d\n", d, n);
    // fprintf(stderr, "  - Input Vector  (X) Dimensions : %d x 1\n", n);
    // fprintf(stderr, "  - Quantization Group Size (GS) : %d\n", GS);
    // fprintf(stderr, "--------------------------------------------------\n");
    // ==========================================================
    
    // 假设Verilog中的K_ACCUM_DEPTH现在是可变的，并且会从sim_config.txt读取。
    // 我们将GS的值写入该文件，从而动态配置硬件。
    const char* config_filename = "sim_config.txt";
    write_sim_config(config_filename, GS);

    // 如果需要调试，可以取消下面的注释来将完整的输入矩阵和向量写入文件。
    // write_full_matrices(x, w, n, d);

    // 初始化最终的浮点输出向量为零
    memset(xout, 0, d * sizeof(float));

    // 按行分块，块的大小为硬件并行度HW_ARRAY_SIZE
    for (int row_base = 0; row_base < d; row_base += HW_ARRAY_SIZE) {
        
        // 为当前处理的一批行（row_base 到 row_base + HW_ARRAY_SIZE - 1）初始化浮点累加器
        float row_accumulators[HW_ARRAY_SIZE] = {0.0f};

        // 按列分块，块的宽度为GS。这确保了每次硬件调用都处理一个完整的量化组。
        for (int col_base = 0; col_base < n; col_base += GS) {

            // 1. 准备输入瓦片：宽度为GS，并写入硬件输入文件
            write_hw_input_tile(x, w, row_base, col_base, n, d, GS);

            // 2. 调用硬件仿真器。仿真器应从sim_config.txt读取累加深度。
            #ifdef USE_VCS
                int ret = system("./simv");
            #else
                int ret = system("vvp tpu_sim");
            #endif
            if (ret != 0) {
                fprintf(stderr, "致命错误：Verilog仿真失败！正在中止。\n");
                exit(1);
            }

            // 3. 读取硬件返回的、对一个完整组进行计算的整数结果
            int32_t hw_results[HW_ARRAY_SIZE];
            read_hw_output(hw_results);

            // 4. 精确反量化：对硬件返回的每个结果，应用其对应组的精确缩放因子
            for (int i = 0; i < HW_ARRAY_SIZE; ++i) {
                int current_row = row_base + i;
                if (current_row < d) {
                    // 确定当前组对应的缩放因子索引
                    int w_s_idx = (current_row * n + col_base) / GS;
                    int x_s_idx = col_base / GS;

                    // 边界检查
                    if (w_s_idx >= (d*n/GS) || x_s_idx >= (n/GS)) continue;

                    // 获取该组精确的缩放因子
                    float s_w = w->s[w_s_idx];
                    float s_x = x->s[x_s_idx];
                    
                    // 计算该组的浮点值，并累加到对应行的总和中
                    row_accumulators[i] += (float)hw_results[i] * s_w * s_x;
                }
            }
        }

        // 遍历完所有列（所有组）后，将这批行计算得到的最终结果写入输出向量xout
        for (int i = 0; i < HW_ARRAY_SIZE; ++i) {
            int current_row = row_base + i;
            if (current_row < d) {
                xout[current_row] = row_accumulators[i];
            }
        }
    }
}