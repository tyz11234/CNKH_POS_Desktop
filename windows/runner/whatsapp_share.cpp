#include "whatsapp_share.h"

#include <windows.h>
#include <shellapi.h>
#include <shlobj.h>

#include <flutter/encodable_value.h>
#include <flutter/method_result_functions.h>

#include <memory>
#include <string>

namespace {

std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  int n = ::MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, nullptr, 0);
  if (n <= 0) return std::wstring();
  std::wstring out(static_cast<size_t>(n - 1), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, out.data(), n);
  return out;
}

std::string UrlEncodeUtf8(const std::string& s) {
  static const char* hex = "0123456789ABCDEF";
  std::string out;
  out.reserve(s.size() * 3);
  for (unsigned char c : s) {
    if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
        (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.' ||
        c == '~') {
      out.push_back(static_cast<char>(c));
    } else if (c == ' ') {
      out.push_back('+');
    } else {
      out.push_back('%');
      out.push_back(hex[c >> 4]);
      out.push_back(hex[c & 0xF]);
    }
  }
  return out;
}

bool CopyFilePathToClipboard(const std::wstring& path) {
  if (path.empty()) return false;
  // DROPFILES + path + double NUL
  const size_t path_bytes = (path.size() + 1) * sizeof(wchar_t);
  const size_t total = sizeof(DROPFILES) + path_bytes + sizeof(wchar_t);
  HGLOBAL hmem = ::GlobalAlloc(GHND, total);
  if (!hmem) return false;
  auto* df = static_cast<DROPFILES*>(::GlobalLock(hmem));
  if (!df) {
    ::GlobalFree(hmem);
    return false;
  }
  df->pFiles = sizeof(DROPFILES);
  df->fWide = TRUE;
  auto* dest = reinterpret_cast<wchar_t*>(reinterpret_cast<BYTE*>(df) +
                                          sizeof(DROPFILES));
  wcsncpy_s(dest, path.size() + 1, path.c_str(), _TRUNCATE);
  // second NUL already zeroed by GHND
  ::GlobalUnlock(hmem);

  if (!::OpenClipboard(nullptr)) {
    ::GlobalFree(hmem);
    return false;
  }
  ::EmptyClipboard();
  if (!::SetClipboardData(CF_HDROP, hmem)) {
    ::CloseClipboard();
    ::GlobalFree(hmem);
    return false;
  }
  ::CloseClipboard();
  // Ownership of hmem transferred to clipboard.
  return true;
}

bool LaunchWhatsAppSend(const std::string& phone, const std::string& text) {
  std::string url = "whatsapp://send?";
  if (!phone.empty()) {
    url += "phone=" + phone + "&";
  }
  url += "text=" + UrlEncodeUtf8(text);
  std::wstring wurl = Utf8ToWide(url);
  HINSTANCE hi =
      ::ShellExecuteW(nullptr, L"open", wurl.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
  return reinterpret_cast<INT_PTR>(hi) > 32;
}

bool SharePdf(const std::string& path, const std::string& text,
              const std::string& phone) {
  std::wstring wpath = Utf8ToWide(path);
  if (wpath.empty() || ::GetFileAttributesW(wpath.c_str()) == INVALID_FILE_ATTRIBUTES) {
    return false;
  }
  // Put PDF on clipboard so user can Ctrl+V into the WhatsApp chat.
  CopyFilePathToClipboard(wpath);
  // Open WhatsApp Desktop chat with caption prefilled.
  if (!LaunchWhatsAppSend(phone, text)) {
    return false;
  }
  return true;
}

}  // namespace

void RegisterWhatsAppShareChannel(flutter::BinaryMessenger* messenger) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "com.cnkh.cnkh_pos_desktop/whatsapp_share",
          &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() != "sharePdf") {
          result->NotImplemented();
          return;
        }
        const auto* args =
            std::get_if<flutter::EncodableMap>(call.arguments());
        if (!args) {
          result->Error("ARG", "expected map arguments");
          return;
        }
        std::string path;
        std::string text;
        std::string phone;
        auto it = args->find(flutter::EncodableValue("path"));
        if (it != args->end()) {
          if (const auto* s = std::get_if<std::string>(&it->second)) path = *s;
        }
        it = args->find(flutter::EncodableValue("text"));
        if (it != args->end()) {
          if (const auto* s = std::get_if<std::string>(&it->second)) text = *s;
        }
        it = args->find(flutter::EncodableValue("phone"));
        if (it != args->end()) {
          if (const auto* s = std::get_if<std::string>(&it->second)) phone = *s;
        }
        if (path.empty()) {
          result->Error("ARG", "path required");
          return;
        }
        try {
          const bool ok = SharePdf(path, text, phone);
          result->Success(flutter::EncodableValue(ok));
        } catch (...) {
          result->Error("SHARE", "sharePdf failed");
        }
      });

  // Keep channel alive for process lifetime (leaked intentionally, like
  // Flutter battery sample; alternatively store on FlutterWindow).
  channel.release();
}
