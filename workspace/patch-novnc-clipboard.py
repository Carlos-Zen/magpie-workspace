from pathlib import Path
import sys


path = Path(sys.argv[1] if len(sys.argv) > 1 else "/usr/share/novnc/app/ui.js")
text = path.read_text()

old_handlers = '''        document.getElementById("noVNC_clipboard_button")
            .addEventListener('click', UI.toggleClipboardPanel);
        document.getElementById("noVNC_clipboard_text")
            .addEventListener('change', UI.clipboardSend);
'''
new_handlers = '''        document.getElementById("noVNC_clipboard_button")
            .addEventListener('click', UI.toggleClipboardPanel);
        document.getElementById("noVNC_clipboard_text")
            .addEventListener('change', UI.clipboardSend);
        // Coder clipboard bridge: visible buttons + keyboard shortcuts.
        UI.initClipboardBridge();
        window.addEventListener('keydown', UI.clipboardKeydown, true);
        document.addEventListener('paste', UI.clipboardPasteEvent, true);
        document.addEventListener('copy', UI.clipboardCopyEvent, true);
'''
if old_handlers not in text:
    raise SystemExit("noVNC clipboard handler block was not found")
text = text.replace(old_handlers, new_handlers, 1)

old_receive = '''    clipboardReceive(e) {
        Log.Debug(">> UI.clipboardReceive: " + e.detail.text.substr(0, 40) + "...");
        document.getElementById('noVNC_clipboard_text').value = e.detail.text;
        Log.Debug("<< UI.clipboardReceive");
    },

    clipboardClear() {
'''
new_receive = '''    clipboardReceive(e) {
        Log.Debug(">> UI.clipboardReceive: " + e.detail.text.substr(0, 40) + "...");
        document.getElementById('noVNC_clipboard_text').value = e.detail.text;
        UI.remoteClipboardText = e.detail.text;
        UI.setClipboardStatus('收到远程剪贴板，正在同步...');
        if (navigator.clipboard && window.isSecureContext) {
            navigator.clipboard.writeText(e.detail.text).then(() => {
                UI.setClipboardStatus('远程剪贴板已自动同步到本机');
            }).catch((err) => {
                UI.setClipboardStatus('远程剪贴板已收到，点“复制到本机”或按 Cmd/Ctrl+C');
                Log.Warn("Unable to write remote clipboard to browser: " + err);
            });
        } else {
            UI.setClipboardStatus('浏览器不支持自动剪贴板同步，请用左侧面板');
        }
        Log.Debug("<< UI.clipboardReceive");
    },

    initClipboardBridge() {
        if (document.getElementById('coderClipboardBridge')) return;
        if (!document.getElementById('coderClipboardPasteTarget')) {
            const target = document.createElement('textarea');
            target.id = 'coderClipboardPasteTarget';
            target.setAttribute('aria-hidden', 'true');
            target.setAttribute('autocomplete', 'off');
            target.style.cssText = 'position:fixed;top:0;left:0;width:1px;height:1px;opacity:0;border:0;padding:0;z-index:-1;pointer-events:none';
            document.body.appendChild(target);
        }
        const bar = document.createElement('div');
        bar.id = 'coderClipboardBridge';
        bar.style.cssText = 'position:fixed;right:12px;bottom:12px;z-index:2147483647;display:flex;gap:6px;align-items:center;padding:6px 8px;border-radius:8px;background:rgba(20,20,30,0.88);color:#fff;font:12px/1.4 system-ui,sans-serif;box-shadow:0 2px 10px rgba(0,0,0,0.35)';
        const paste = document.createElement('button');
        paste.id = 'coderClipboardPaste';
        paste.textContent = '粘贴到远程';
        paste.title = '读取本机剪贴板并粘贴到远程 Chromium；首次使用请允许剪贴板权限';
        paste.style.cssText = 'cursor:pointer;border:0;border-radius:5px;padding:3px 8px;background:#2563eb;color:#fff;font:12px system-ui,sans-serif';
        const copy = document.createElement('button');
        copy.id = 'coderClipboardCopy';
        copy.textContent = '复制到本机';
        copy.title = '把最近一次远程剪贴板内容写入本机剪贴板';
        copy.style.cssText = paste.style.cssText;
        const status = document.createElement('span');
        status.id = 'coderClipboardStatus';
        status.textContent = '剪贴板桥 v7';
        status.style.cssText = 'max-width:260px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;opacity:0.9';
        bar.appendChild(paste);
        bar.appendChild(copy);
        bar.appendChild(status);
        document.body.appendChild(bar);
        paste.addEventListener('click', () => UI.pasteFromLocal());
        copy.addEventListener('click', () => UI.copyToLocal());
        UI.updateClipboardStatus();
    },

    setClipboardStatus(text) {
        const status = document.getElementById('coderClipboardStatus');
        if (status) status.textContent = text;
    },

    updateClipboardStatus() {
        if (!navigator.clipboard) {
            UI.setClipboardStatus('浏览器不支持剪贴板 API');
            return;
        }
        if (!window.isSecureContext) {
            UI.setClipboardStatus('需要 HTTPS 才能使用剪贴板');
            return;
        }
        if (navigator.permissions && navigator.permissions.query) {
            navigator.permissions.query({name: 'clipboard-read'}).then((p) => {
                UI.clipboardReadState = p.state;
                if (p.state === 'denied') {
                    UI.setClipboardStatus('剪贴板读取被拒绝：Cmd+V 使用系统粘贴');
                } else if (p.state === 'prompt') {
                    UI.setClipboardStatus('剪贴板桥 v7（Cmd+V 可直接粘贴）');
                } else {
                    UI.setClipboardStatus('剪贴板桥 v7 就绪');
                }
            }).catch(() => {});
        }
    },

    async pasteFromLocal() {
        if (!UI.rfb) {
            UI.setClipboardStatus('远程桌面尚未连接');
            return;
        }
        if (!navigator.clipboard || !navigator.clipboard.readText) {
            UI.setClipboardStatus('浏览器不支持读取剪贴板，请用左侧剪贴板面板');
            return;
        }
        try {
            const text = await navigator.clipboard.readText();
            if (!text) {
                UI.setClipboardStatus('本机剪贴板为空');
                return;
            }
            UI.rfb.clipboardPasteFrom(text);
            UI.setClipboardStatus('已发送到远程，正在粘贴：' + text.slice(0, 24) + (text.length > 24 ? '...' : ''));
            setTimeout(() => UI.sendRemotePaste(), 200);
        } catch (err) {
            UI.setClipboardStatus('读取本机剪贴板失败：请在地址栏允许剪贴板权限');
            Log.Warn("Unable to read browser clipboard: " + err);
        }
    },

    async copyToLocal() {
        const text = UI.remoteClipboardText || '';
        if (!text) {
            UI.setClipboardStatus('远程剪贴板还没有内容：先在远程 Chromium 中复制一次');
            return;
        }
        if (!navigator.clipboard || !navigator.clipboard.writeText) {
            UI.setClipboardStatus('浏览器不支持写入剪贴板，请用左侧剪贴板面板');
            return;
        }
        try {
            await navigator.clipboard.writeText(text);
            UI.setClipboardStatus('已复制到本机：' + text.slice(0, 24) + (text.length > 24 ? '...' : ''));
        } catch (err) {
            UI.setClipboardStatus('写入本机剪贴板失败：请允许剪贴板权限');
            Log.Warn("Unable to write remote clipboard to browser: " + err);
        }
    },

    sendRemotePaste() {
        const input = document.getElementById('noVNC_keyboardinput');
        if (!input) {
            UI.setClipboardStatus('已写入远程剪贴板；请按一次 Ctrl/Cmd+V');
            return;
        }
        const fire = (type, key, code, keyCode, ctrlKey) => {
            input.dispatchEvent(new KeyboardEvent(type, {
                key: key,
                code: code,
                keyCode: keyCode,
                which: keyCode,
                ctrlKey: ctrlKey,
                metaKey: false,
                bubbles: true,
                cancelable: true
            }));
        };
        UI.syntheticPaste = true;
        input.focus();
        // macOS Cmd is already forwarded as Super_L down; release it before Ctrl+V,
        // otherwise the remote app receives Super+Ctrl+V instead of Ctrl+V.
        if (UI.rfb && typeof UI.rfb.sendKey === 'function') {
            UI.rfb.sendKey(0xffe9, 'MetaLeft', false);
        }
        fire('keyup', 'Meta', 'MetaLeft', 91, false);
        fire('keydown', 'Control', 'ControlLeft', 17, true);
        fire('keydown', 'v', 'KeyV', 86, true);
        fire('keyup', 'v', 'KeyV', 86, true);
        fire('keyup', 'Control', 'ControlLeft', 17, false);
        UI.setClipboardStatus('已粘贴到远程（Ctrl+V）');
        setTimeout(() => {
            UI.syntheticPaste = false;
            UI.restoreKeyboardFocus();
        }, 50);
    },

    focusPasteTarget() {
        const target = document.getElementById('coderClipboardPasteTarget');
        if (!target) return;
        target.value = '';
        try { target.focus({preventScroll: true}); } catch (err) { target.focus(); }
    },

    restoreKeyboardFocus() {
        setTimeout(() => {
            const input = document.getElementById('noVNC_keyboardinput');
            if (input && typeof input.focus === 'function') {
                try { input.focus({preventScroll: true}); return; } catch (err) {}
            }
            const canvas = document.querySelector('#noVNC_container canvas');
            if (canvas && typeof canvas.focus === 'function') {
                try { canvas.focus({preventScroll: true}); } catch (err) {}
            }
        }, 30);
    },

    clipboardPasteEvent(e) {
        if (!UI.rfb || !e.clipboardData) return;
        const text = e.clipboardData.getData('text/plain');
        if (text === '') return;
        e.preventDefault();
        e.stopPropagation();
        UI.pasteFallbackPending = false;
        UI.rfb.clipboardPasteFrom(text);
        UI.setClipboardStatus('已发送到远程（系统粘贴），正在粘贴：' + text.slice(0, 24) + (text.length > 24 ? '...' : ''));
        UI.restoreKeyboardFocus();
        setTimeout(() => UI.sendRemotePaste(), 200);
    },

    clipboardKeydown(e) {
        if (UI.syntheticPaste) return;
        if (!UI.rfb || !(e.ctrlKey || e.metaKey) || e.key.toLowerCase() !== 'v') return;
        // Let the browser perform a native paste into the hidden target: this does
        // not require clipboard-read permission. Do NOT preventDefault here.
        e.stopPropagation();
        UI.focusPasteTarget();
        UI.pasteFallbackPending = true;
        setTimeout(() => {
            if (!UI.pasteFallbackPending) return;
            UI.pasteFallbackPending = false;
            UI.restoreKeyboardFocus();
            if (navigator.clipboard && navigator.clipboard.readText) {
                UI.pasteFromLocal();
            } else {
                UI.setClipboardStatus('无法读取剪贴板，请点“粘贴到远程”');
            }
        }, 350);
    },

    clipboardCopyEvent(e) {
        if (!UI.remoteClipboardText || !e.clipboardData) return;
        e.preventDefault();
        e.stopPropagation();
        e.clipboardData.setData('text/plain', UI.remoteClipboardText);
        UI.setClipboardStatus('已把远程剪贴板写入本机');
    },

    clipboardClear() {
'''
if old_receive not in text:
    raise SystemExit("noVNC clipboard receive block was not found")
text = text.replace(old_receive, new_receive, 1)
path.write_text(text)
print("patched:", path)
