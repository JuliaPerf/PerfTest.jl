export MODEL_DIR=$WORK/models
# old
export LLAMA_LIB=/home/hpc/j101df/j101df19/llamacpp/llama.cpp/build/bin/libllama.so
# new
export LLAMA_LIB=$WORK/llama.cpp/build/$HOSTNAME/bin/libllama.so
export LLAMA_DIR=$WORK/llama.cpp/build/$HOSTNAME/bin
export LD_LIBRARY_PATH=$LLAMA_DIR:$LD_LIBRARY_PATH
