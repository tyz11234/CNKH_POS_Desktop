#ifndef RUNNER_WHATSAPP_SHARE_H_
#define RUNNER_WHATSAPP_SHARE_H_

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>

namespace flutter {
class BinaryMessenger;
}

// Registers MethodChannel com.cnkh.cnkh_pos_desktop/whatsapp_share
// method sharePdf {path, text, phone} — opens WhatsApp Desktop and copies
// the PDF to the clipboard as CF_HDROP for Ctrl+V into the chat.
void RegisterWhatsAppShareChannel(flutter::BinaryMessenger* messenger);

#endif  // RUNNER_WHATSAPP_SHARE_H_
