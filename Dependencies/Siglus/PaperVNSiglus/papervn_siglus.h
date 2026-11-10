#ifndef PAPERVN_SIGLUS_H
#define PAPERVN_SIGLUS_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* 0：不需要密钥或 key.toml 里的密钥可用；1：缺少可用的密钥（siglus_ios_create 会暴力推算很久）；2：文件无效。 */
int32_t papervn_siglus_key_status(const char *project_dir_utf8);

/* siglus_rs 的 ios_host.rs 导出但 siglus.h 没有声明的按键接口（Windows 虚拟键码，例如 0x1B Esc、0x11 Ctrl）。 */
void siglus_ios_key_down(void *handle, int32_t key_code);
void siglus_ios_key_up(void *handle, int32_t key_code);

#ifdef __cplusplus
}
#endif

#endif
