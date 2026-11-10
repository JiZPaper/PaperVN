// 照 krkr2 的 cpp/core/environ/apple/macos/platform.mm 改成 iOS 版：去掉 AppKit，
// 提示框、输入框、退出交给 PaperVN（PaperVNKiriKiriHost）。
//
// Created by LiDong on 2025/8/24.
//
#include <string>
#include <filesystem>
#include <vector>
#include <algorithm>
#include <CoreFoundation/CoreFoundation.h>
#include <mach-o/dyld.h>
#include <mach/task.h>
#include <mach/vm_statistics.h>
#include <mach/mach_host.h>
#include <mach/mach_init.h>
#include <unistd.h>

#include <sys/stat.h>
#include <sys/time.h>
#include <sys/sysctl.h>

#import <Foundation/Foundation.h>
#include <sstream>

#include "PaperVNKiriKiriHost.h"

#include <cocos2d.h>

#include "StorageImpl.h"
#include "EventIntf.h"
#include "Platform.h"
#include "tjsString.h"

bool TVPDeleteFile(const std::string &filename) {
    return unlink(filename.c_str()) == 0;
}

bool TVPRenameFile(const std::string &from, const std::string &to) {
    tjs_int ret = rename(from.c_str(), to.c_str());
    return !ret;
}

bool TVPCreateFolders(const ttstr &folder);

static bool _TVPCreateFolders(const ttstr &folder) {
    // create directories along with "folder"
    if(folder.IsEmpty())
        return true;

    if(TVPCheckExistentLocalFolder(folder))
        return true; // already created

    const tjs_char *p = folder.c_str();
    tjs_int i = folder.GetLen() - 1;

    if(p[i] == TJS_W(':'))
        return true;

    while(i >= 0 && (p[i] == TJS_W('/') || p[i] == TJS_W('\\')))
        i--;

    if(i >= 0 && p[i] == TJS_W(':'))
        return true;

    for(; i >= 0; i--) {
        if(p[i] == TJS_W(':') || p[i] == TJS_W('/') || p[i] == TJS_W('\\'))
            break;
    }

    ttstr parent(p, i + 1);
    if(!TVPCreateFolders(parent))
        return false;

    // create_directory 新建成功返回 true，已存在返回 false，都算成功
    std::error_code error;
    std::filesystem::create_directory(folder.AsStdString().c_str(), error);
    return !error;
}

bool TVPCreateFolders(const ttstr &folder) {
    if(folder.IsEmpty())
        return true;

    const tjs_char *p = folder.c_str();
    tjs_int i = folder.GetLen() - 1;

    if(p[i] == TJS_W(':'))
        return true;

    if(p[i] == TJS_W('/') || p[i] == TJS_W('\\'))
        i--;

    return _TVPCreateFolders(ttstr(p, i + 1));
}

std::vector<std::string> GetAccessibleDirectories() {
    std::vector<std::string> result;
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    if(paths.count > 0) {
        result.emplace_back([paths.firstObject UTF8String]);
    }
    return result;
}

/// StorageImpl.cpp 在 iOS 上用它把沙盒路径前缀当成不区分大小写处理
const std::vector<std::string> &TVPGetApplicationHomeDirectory() {
    static std::vector<std::string> result{ [NSHomeDirectory() UTF8String] };
    return result;
}

std::vector<std::string> TVPGetDriverPath() {
    return GetAccessibleDirectories();
}

void TVPGetMemoryInfo(TVPMemoryInfo &m) {
    // 初始化所有字段为0
    m.MemTotal = 0;
    m.MemFree = 0;
    m.SwapTotal = 0;
    m.SwapFree = 0;
    m.VirtualTotal = 0;
    m.VirtualUsed = 0;

    // 获取物理内存总量
    int mib[2];
    int64_t total_memory;
    size_t length = sizeof(total_memory);

    mib[0] = CTL_HW;
    mib[1] = HW_MEMSIZE;
    if (sysctl(mib, 2, &total_memory, &length, nullptr, 0) == 0) {
        m.MemTotal = total_memory / 1024; // 转换为KB
    }

    // 获取内存统计信息
    vm_size_t page_size;
    vm_statistics64_data_t vm_stats;
    mach_port_t mach_port = mach_host_self();
    mach_msg_type_number_t count = sizeof(vm_stats) / sizeof(natural_t);

    if (host_page_size(mach_port, &page_size) == KERN_SUCCESS &&
        host_statistics64(mach_port, HOST_VM_INFO, (host_info64_t)&vm_stats, &count) == KERN_SUCCESS) {
        // 计算可用内存 (空闲内存 + 非活跃内存)
        int64_t free_memory = (vm_stats.free_count + vm_stats.inactive_count) * page_size;
        m.MemFree = free_memory / 1024; // 转换为KB
    }

    // 获取交换空间信息
    xsw_usage swap_usage{};
    size_t swap_size = sizeof(swap_usage);
    mib[0] = CTL_VM;
    mib[1] = VM_SWAPUSAGE;

    if (sysctl(mib, 2, &swap_usage, &swap_size, nullptr, 0) == 0) {
        m.SwapTotal = swap_usage.xsu_total / 1024; // 转换为KB
        m.SwapFree = (swap_usage.xsu_total - swap_usage.xsu_used) / 1024; // 转换为KB
    }

    // macOS 没有直接的 Vmalloc 概念，但可以获取虚拟内存信息
    // 这里使用进程虚拟内存大小作为近似值
    struct task_basic_info_64 info{};
    mach_msg_type_number_t info_count = TASK_BASIC_INFO_64_COUNT;

    if (task_info(mach_task_self(), TASK_BASIC_INFO_64, (task_info_t)&info, &info_count) == KERN_SUCCESS) {
        m.VirtualTotal = info.virtual_size / 1024; // 转换为KB
        m.VirtualUsed = info.resident_size / 1024; // 转换为KB
    }
}

void TVPRelinquishCPU() {
    sched_yield();
}

void TVPSendToOtherApp(const std::string &filename) {}

bool TVPCheckStartupArg() {
    return false;
}

void TVPControlAdDialog(int, int, int) { /*pass*/ }

void TVPExitApplication(int code) {
    // iOS 上不能结束整个 App：停下引擎，由 PaperVN 关闭运行页面
    TVPDeliverCompactEvent(TVP_COMPACT_LEVEL_MAX);
    PaperVNKiriKiriHostRequestExit(code);
}

void TVPForceSwapBuffer() { /* pass */ }

bool TVPWriteDataToFile(const ttstr &filepath, const void *data,
                        unsigned int len) {
    FILE *handle = fopen(filepath.AsStdString().c_str(), "wb");
    if(handle) {
        bool ret = fwrite(data, 1, len, handle) == len;
        fclose(handle);
        return ret;
    }
    return false;
}

bool TVPCheckStartupPath(const std::string &path) { return true; }

std::string TVPGetDefaultFileDir() {
    return PaperVNKiriKiriHostDataPath();
}

std::vector<std::string> TVPGetAppStoragePath() {
    std::vector<std::string> ret;
    ret.emplace_back(TVPGetDefaultFileDir());
    return ret;
}

tjs_int TVPGetSelfUsedMemory() {
    mach_task_basic_info info{};
    mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;

    kern_return_t kr = task_info(mach_task_self(), MACH_TASK_BASIC_INFO,
                                (task_info_t)&info, &count);
    if (kr != KERN_SUCCESS) {
        return -1;
    }

    // 返回驻留内存大小（字节转换为MB）
    return info.resident_size / (1024 * 1024);
}

std::string TVPGetCurrentLanguage() {
    CFArrayRef preferredLanguages = CFLocaleCopyPreferredLanguages();
    if (preferredLanguages == nullptr || CFArrayGetCount(preferredLanguages) == 0) {
        return "en_US"; // 默认值
    }

    auto preferredLanguage = (CFStringRef)CFArrayGetValueAtIndex(preferredLanguages, 0);
    char buffer[256];
    CFStringGetCString(preferredLanguage, buffer, sizeof(buffer), kCFStringEncodingUTF8);
    std::string localeStr(buffer);
    CFRelease(preferredLanguages);

    // 替换连字符为下划线
    std::replace(localeStr.begin(), localeStr.end(), '-', '_');

    // 分割字符串部分
    std::vector<std::string> parts;
    std::istringstream iss(localeStr);
    std::string part;
    while (std::getline(iss, part, '_')) {
        parts.push_back(part);
    }

    if (parts.empty()) {
        return "en_US";
    }

    // 提取语言代码（第一部分）
    std::string language = parts[0];

    // 查找国家代码（最后一个两部分字母的部分，通常是国家代码）
    std::string country;
    for (size_t i = parts.size() - 1; i > 0; --i) {
        if (parts[i].size() == 2) {
            country = parts[i];
            break;
        }
    }

    // 如果没有找到国家代码，检查是否有类似"CN"的代码
    if (country.empty() && parts.size() > 1) {
        // 检查最后一个部分是否为2字母代码（国家代码）
        const std::string& lastPart = parts.back();
        if (lastPart.size() == 2) {
            country = lastPart;
        }
    }

    // 转换国家代码为小写
    std::transform(country.begin(), country.end(), country.begin(), ::tolower);

    // 组合结果
    if (!country.empty()) {
        return language + "_" + country;
    } else {
        return language;
    }
}

void TVPProcessInputEvents() { /* pass */ }

int TVPShowSimpleInputBox(ttstr &text, const ttstr &caption,
                          const ttstr &prompt,
                          const std::vector<ttstr> &vecButtons) {
    std::vector<std::string> buttons;
    for(const auto &button : vecButtons) buttons.emplace_back(button.AsStdString());
    std::string value = text.AsStdString();
    int result = PaperVNKiriKiriHostInputBox(caption.AsStdString(), prompt.AsStdString(), value, buttons);
    text = ttstr(value.c_str());
    return result;
}

tjs_uint32 TVPGetRoughTickCount32() {
    tjs_uint32 uptime = 0;
    timespec on{};
    if(clock_gettime(CLOCK_MONOTONIC, &on) == 0)
        uptime = on.tv_sec * 1000 + on.tv_nsec / 1000000;
    return uptime;
}


tjs_int TVPGetSystemFreeMemory() {
    // 使用 Mach API 获取内存统计
    vm_statistics64_data_t vm_stats;
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    kern_return_t kern_return = host_statistics64(mach_host_self(),
                                                HOST_VM_INFO64,
                                                (host_info64_t)&vm_stats,
                                                &count);

    if (kern_return != KERN_SUCCESS) {
        return -1;
    }

    // 获取页大小
    vm_size_t page_size;
    host_page_size(mach_host_self(), &page_size);

    // 计算可用内存 (空闲内存 + 非活跃内存)
    natural_t free_memory = (vm_stats.free_count + vm_stats.inactive_count) * page_size;

    // 转换为 MB
    return free_memory / (1024 * 1024);
}

int TVPShowSimpleMessageBox(const ttstr &text, const ttstr &caption,
                            const std::vector<ttstr> &vecButtons) {
    std::vector<std::string> buttons;
    for(const auto &button : vecButtons) buttons.emplace_back(button.AsStdString());
    return PaperVNKiriKiriHostMessageBox(caption.AsStdString(), text.AsStdString(), buttons);
}

extern "C" int TVPShowSimpleMessageBox(const char *pszText, const char *pszTitle,
                            unsigned int nButton, const char **btnText) {
    std::vector<ttstr> vecButtons{};
    for(u_int i = 0; i < nButton; ++i) {
        vecButtons.emplace_back(btnText[i]);
    }
    return TVPShowSimpleMessageBox(pszText, pszTitle, vecButtons);
}

std::string TVPGetPackageVersionString() {
    return "ios";
}

bool TVP_stat(const char *name, tTVP_stat &s) {
    struct stat t{};
    if(stat(name, &t) != 0) {
        return false;
    }

    s.st_mode = t.st_mode;
    s.st_size = t.st_size;
    s.st_atime = t.st_atimespec.tv_sec; // 最后访问时间（秒）
    s.st_mtime = t.st_mtimespec.tv_sec; // 最后修改时间（秒）
    s.st_ctime = t.st_ctimespec.tv_sec; // 最后状态更改时间（秒）

    return true; // 成功
}

bool TVP_stat(const tjs_char *name, tTVP_stat &s) {
    return TVP_stat(ttstr{ name }.AsStdString().c_str(), s);
}

bool TVP_utime(const char *name, time_t modtime) {
    timeval mt[2];
    mt[0].tv_sec = modtime;
    mt[0].tv_usec = 0;
    mt[1].tv_sec = modtime;
    mt[1].tv_usec = 0;
    return utimes(name, mt) == 0;
}

