// PaperVN：krkrlive2d（吉里吉里Z）编进 krkr2
#pragma once
#include "tp_stub.h"
#include <string>
using tjs_string = std::u16string;
using iTJSBinaryStream = tTJSBinaryStream;
#include "StorageIntf.h"
#define NCB_MODULE_NAME TJS_W("krkrlive2d.dll")
#ifndef TJS_BS_SEEK_SET
#define TJS_BS_SEEK_SET 0
#define TJS_BS_SEEK_CUR 1
#define TJS_BS_SEEK_END 2
#endif
