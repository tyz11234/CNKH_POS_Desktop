from pathlib import Path

p = Path('README.md')
s = p.read_text(encoding='utf-8')
heading = '## 2026-09-06 分页与双端联调补强\n'
if heading not in s:
    anchor = '## OCR Purchase 架构\n'
    section = '''## 2026-09-06 分页与双端联调补强

本轮针对 Mobile 大数据量分页与 Release 联网问题做配套回归。Desktop 保持现有 Windows UI 与业务逻辑，不复制 Mobile 的分页 UI；主要修正双端测试基线与依赖一致性。

- Desktop / Mobile 联调不再固定到旧 Mobile SHA；工作流会记录并测试明确的双端 ref / SHA。
- Desktop 的 `google_mlkit_text_recognition` 已与当前 Mobile 对齐到 `^0.16.0`，并刷新 `pubspec.lock`，避免最新两端无法共同解析依赖。
- 最新两端组合已通过真实 localhost HTTP 同步与重连回归，包括：离线操作顺序、盘点冲突、服务器恢复重连、进货 Lost-ACK 幂等、PC Void 传播等。
- Mobile 的分页改动不改变 LAN `cnkh-sync:v1` 协议，也不改变 Desktop 权威库存模型。
- 最终合并前仍要求 Desktop `flutter analyze`、`flutter test`、Windows Release build 与双端 integration 全部通过。

真机 Android 局域网测试不由 CI 冒充；若未连接实体 Android 设备，会在验证记录中明确标记未执行。

'''
    if anchor not in s:
        raise SystemExit('README anchor not found')
    p.write_text(s.replace(anchor, section + anchor, 1), encoding='utf-8')
