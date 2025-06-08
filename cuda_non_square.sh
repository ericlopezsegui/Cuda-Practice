#!/bin/bash

BLOCK_DIMS=("2x1" "4x2" "16x2")
SIZES=(100 1000 2000)
STEPS=(100 1000 10000 100000)

RESULTS_DIR="cuda_non_square"
CSV_FILE="${RESULTS_DIR}/cuda_non_square_results.csv"

mkdir -p "$RESULTS_DIR"
echo "ThreadsPerBlock,BlockX,BlockY,Time(s),Size,Steps,OutputFile" > "$CSV_FILE"

for CONFIG in "${BLOCK_DIMS[@]}"; do
  BLOCK_X=$(echo "$CONFIG" | cut -d'x' -f1)
  BLOCK_Y=$(echo "$CONFIG" | cut -d'x' -f2)
  THREADS_PER_BLOCK=$((BLOCK_X * BLOCK_Y))
  CONFIG_NAME="block_${BLOCK_X}x${BLOCK_Y}"
  CONFIG_DIR="${RESULTS_DIR}/${CONFIG_NAME}"

  echo "=== Testing ${CONFIG_NAME} (${THREADS_PER_BLOCK}) ==="
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
        TIME_MS=$(grep "Execution time" "$LOG_FILE" | grep -oP '(?<=Execution time: )[\d.]+')
        [[ -n "$TIME_MS" ]] && TIME_S=$(awk "BEGIN {printf \"%.6f\", $TIME_MS / 1000}") || TIME_S="N/A"
        echo "${THREADS_PER_BLOCK},${BLOCK_X},${BLOCK_Y},${TIME_S},${SIZE},${STEP},${OUTPUT_FILE}" >> "$CSV_FILE"
      fi

    done
  done
done

echo "Benchmark finished. Results in $CSV_FILE"
