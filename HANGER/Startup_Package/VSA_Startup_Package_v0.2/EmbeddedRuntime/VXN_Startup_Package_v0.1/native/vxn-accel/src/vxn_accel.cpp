#include "vxn_accel.h"
int64_t vxn_sum_i64(const int64_t* values, size_t len){int64_t sum=0;for(size_t i=0;i<len;++i){sum+=values[i];}return sum;}
