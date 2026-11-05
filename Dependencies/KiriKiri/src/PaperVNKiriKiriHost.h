// 引擎（platform_ios.mm）调用 PaperVN 的部分，实现在 PaperVNKiriKiri.mm。
#pragma once
#include <string>
#include <vector>

void PaperVNKiriKiriHostRequestExit(int code);
std::string PaperVNKiriKiriHostDataPath();
int PaperVNKiriKiriHostMessageBox(const std::string &title, const std::string &message,
                                  const std::vector<std::string> &buttons);
int PaperVNKiriKiriHostInputBox(const std::string &title, const std::string &prompt, std::string &text,
                                const std::vector<std::string> &buttons);
