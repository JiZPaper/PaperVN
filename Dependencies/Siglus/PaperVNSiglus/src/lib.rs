//! PaperVN 自己的 C 接口。脚本用了游戏自己的密钥、又没有可用的 key.toml 时，
//! `siglus_ios_create` 会在主线程上暴力推算密钥，要十几分钟以上；PaperVN 先用
//! `papervn_siglus_key_status` 检查，这种情况下不创建引擎，提示使用适配模拟器的版本。

use std::ffi::{CStr, c_char};
use std::path::Path;

// 让 game_launcher 的 siglus_* / game_* 接口留在静态库里
pub use game_launcher;

/// 0：不需要密钥或 key.toml 里的密钥可用，可以直接开始；1：缺少可用的密钥；2：文件无效。
#[unsafe(no_mangle)]
pub unsafe extern "C" fn papervn_siglus_key_status(project_dir_utf8: *const c_char) -> i32 {
    if project_dir_utf8.is_null() {
        return 2;
    }
    let Ok(text) = (unsafe { CStr::from_ptr(project_dir_utf8) }).to_str() else {
        return 2;
    };
    match status(Path::new(text)) {
        Ok(true) => 0,
        Ok(false) => 1,
        Err(code) => code,
    }
}

fn resources(project: &Path) -> Result<(Vec<u8>, Vec<u8>), i32> {
    use siglus_scene_vm::resource::{find_initial_gameexe_path, find_scene_pck_path, read_file_bytes};
    let game = find_initial_gameexe_path(project).and_then(|p| read_file_bytes(&p)).map_err(|_| 2)?;
    let scene = find_scene_pck_path(project).and_then(|p| read_file_bytes(&p)).map_err(|_| 2)?;
    Ok((game, scene))
}

/// 和 siglus_rs 的 `resolve_project_exe_key` 判断一致：true 表示创建引擎时不会推算密钥。
fn status(project: &Path) -> Result<bool, i32> {
    use siglus_key_recovery::{KeyStatus, check_key, resources_require_exe_key, scene_pack_is_compressed};
    let (game, scene) = resources(project)?;
    if !resources_require_exe_key(&game, &scene).unwrap_or(false) {
        return Ok(true);
    }
    if let Ok(Some(key)) = siglus_assets::key_toml::load_key16_from_project_dir(project) {
        if matches!(check_key(&game, &scene, &key), Ok(KeyStatus::Accepted | KeyStatus::Unverifiable)) {
            return Ok(true);
        }
    }
    // 不压缩的封包无法推算，引擎也会跳过
    Ok(scene_pack_is_compressed(&scene) == Ok(false))
}
