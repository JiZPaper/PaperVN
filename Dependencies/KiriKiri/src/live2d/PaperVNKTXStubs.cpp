// PaperVN：KTX 只保留读取和转码。ASTC 解码（astc-encoder）只有“转成未压缩格式再用”时才要，
// Live2D 驱动不走这条路径，iOS 也能直接用 ASTC，所以不编 astc-encoder。
#include <ktx.h>
extern "C" KTX_error_code ktxTexture2_DecodeAstc(ktxTexture2 *) { return KTX_UNSUPPORTED_FEATURE; }
