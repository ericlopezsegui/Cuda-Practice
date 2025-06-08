#!/bin/bash

BLOCK_SIZES=(2 4 8 16 32)
SIZES=(100 1000 2000)
STEPS=(100 1000 10000 100000)

RESULTS_DIR="cuda_results"
mkdir -p "$RESULTS_DIR"

CSV_LOG="$RESULTS_DIR/cuda_results.csv"
echo "ThreadsPerBlock,Time(s),Size,Steps,OutputFile" > "$CSV_LOG"

for BLOCK in "${BLOCK_SIZES[@]}"; do
  BLOCK_X=$BLOCK
  BLOCK_Y=$BLOCK
  THREADS_PER_BLOCK=$((BLOCK_X * BLOCK_Y))
  CONFIG_NAME="block_${BLOCK_X}x${BLOCK_Y}"
  CONFIG_DIR="${RESULTS_DIR}/${CONFIG_NAME}"

  echo "=== Testing ${CONFIG_NAME} ==="
  mkdir -p "$CONFIG_DIR"

  for SIZE in "${SIZES[@]}"; do
    SIZE_DIR="${CONFIG_DIR}/size_${SIZE}"
    mkdir -p "$SIZE_DIR"

    for STEP in "${STEPS[@]}"; do
      JOB_NAME="heat_${CONFIG_NAME}_${SIZE}_${STEP}"
      OUTPUT_FILE="${SIZE_DIR}/${JOB_NAME}.bmp"
      LOG_FILE="${SIZE_DIR}/${JOB_NAME}.log"

      echo "Running ${JOB_NAME} ..."
      ./heat_cuda "$SIZE" "$STEP" "$OUTPUT_FILE" "$BLOCK_X" "$BLOCK_Y" > "$LOG_FILE" 2>&1

      if [[ -f "$LOG_FILE" ]]; then
        TIME_MS=$(grep "Execution time" "$LOG_FILE" | awk '{print $3}')
        if [[ -n "$TIME_MS" ]]; then
          TIME_S=$(awk "BEGIN {printf \"%.6f\", $TIME_MS / 1000}")
        else
          TIME_S="N/A"
        fi

        echo "${THREADS_PER_BLOCK},${TIME_S},${SIZE},${STEP},${OUTPUT_FILE}" >> "$CSV_LOG"
      fi

    done
  done
done

echo "Benchmark finished. Results in $CSV_LOG"
