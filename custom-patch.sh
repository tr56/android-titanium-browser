#!/usr/bin/env bash
# Кастомные патчи Titanium (накладываются ПОСЛЕ upstream patch.sh).
# 1. Минцифры root CA, ограниченный зонами .ru / .xn--p1ai (.рф) / .su.
# 2. Исправление GN-зависимости bookmark_import_export_helper -> mojom.
# 3. Сохранение попапа расширений и WebContents при системном выборе файлов (Issue #252).
#
# ВАЖНО: этот файл отдельный, чтобы patch.sh можно было обновлять копированием
# из upstream без повторного вклеивания блока Минцифры.

set -euo pipefail

echo "=== [custom] Патч Минцифры CA (scoped .ru, .xn--p1ai, .su) ==="

python3 - << 'EOF'
import base64, hashlib
from pathlib import Path

# Сертификат Минцифры (Russian Trusted Root CA), DER.
# SHA-256: d26d2d0231b7c39f92cc738512ba54103519e4405d68b5bd703e9788ca8ecf31
ca_b64 = (
    "MIIFwjCCA6qgAwIBAgICEAAwDQYJKoZIhvcNAQELBQAwcDELMAkGA1UEBhMCUlUxPzA9BgNVBAoM"
    "NlRoZSBNaW5pc3RyeSBvZiBEaWdpdGFsIERldmVsb3BtZW50IGFuZCBDb21tdW5pY2F0aW9uczEg"
    "MB4GA1UEAwwXUnVzc2lhbiBUcnVzdGVkIFJvb3QgQ0EwHhcNMjIwMzAxMjEwNDE1WhcNMzIwMjI3"
    "MjEwNDE1WjBwMQswCQYDVQQGEwJSVTE/MD0GA1UECgw2VGhlIE1pbmlzdHJ5IG9mIERpZ2l0YWwg"
    "RGV2ZWxvcG1lbnQgYW5kIENvbW11bmljYXRpb25zMSAwHgYDVQQDDBdSdXNzaWFuIFRydXN0ZWQg"
    "Um9vdCBDQTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAMfFOZ8pUAL3+r2nqqE0Zp52"
    "selXsKGFYoG0GM5bwz1bSFtCt+AZQMhkWQheI3poZAToYJu69pHLKS6QXBiwBC1cvzYmUYKMYZC7"
    "jE5YhEU2bSL0mX7NaMxMDmH2/NwuOVRj8OImVa5s1F4Uzn4Kv3PFlDBjjSjXKVY9kmjUBsXQrIHe"
    "aqmUIsPIlNWUnimXS0I0abExqkbdrXbXYwCOXhOO2pDUx3ckmJlCMUGacUTnylyQW2VsJIyIGA8V"
    "0xzdaeUXg0VZ6ZmNUr5YBer/EAOLPb8NYpsAhJe2mXjMB/J9HNsoFMBFJ0lLOT/+dQvjbdRZoOT8"
    "eqJpWnVDU+QL/qEZnz57N88OWM3rabJkRNdU/Z7x5SFIM9FrqtN8xewsiBWBI0K6XFuOBOTD4V08"
    "o4TzJ8+Ccq5XlCUW2L48pZNCYuBDfBh7FxkB7qDgGDiaftEkZZfApRg2E+M9G8wkNKTPLDc4wH0F"
    "DTijhgxR3Y4PiS1HL2Zhw7bD3CbslmEGgfnnZojNkJtcLeBHBLa52/dSwNU4WWLubaYSiAmA9IUM"
    "X1/RpfpxOxd4Ykmhz97oFbUaDJFipIggx5sXePAlkTdWnv+RWBxlJwMQ25oEHmRguNYf4Zr/Rxr9"
    "cS93Y+mdXIZaBEE0KS2iLRqaOiWBki9IMQU4phqPOBAaG7A+eP8PAgMBAAGjZjBkMB0GA1UdDgQW"
    "BBTh0YHlzlpfBKrS6badZrHF+qwshzAfBgNVHSMEGDAWgBTh0YHlzlpfBKrS6badZrHF+qwshzAS"
    "BgNVHRMBAf8ECDAGAQH/AgEEMA4GA1UdDwEB/wQEAwIBhjANBgkqhkiG9w0BAQsFAAOCAgEAALIY"
    "1wkilt/urfEVM5vKzr6utOeDWCUczmWX/RX4ljpRdgF+5fAIS4vHtmXkqpSCOVeWUrJV9QvZn6L2"
    "27ZwuE15cWi8DCDal3Ue90WgAJJZMfTshN4OI8cqW9E4EG9wglbEtMnObHlms8F3CHmrw3k6KmUk"
    "WGoa+/ENmcVl68u/cMRl1JbW2bM+/3A+SAg2c6iPDlehczKx2oa95QW0SkPPWGuNA/CE8CpyANIh"
    "u9XFrj3RQ3EqeRcSAQQod1RNuHpfETLU/A2gMmvn/w/sx7TB3W5BPs6rprOA37tutPq9u6FTZOcG"
    "1OqjC/B7yTqgI7rbyvox7DEXoX7rIiEqyNNUguTk/u3SZ4VXE2kmxdmSh3TQvybfbnXV4JbCZVaq"
    "iZraqc7oZMnRoWrXRG3ztbnbes/9qhRGI7PqXqeKJBztxRTEVj8ONs1dWN5szTwaPIvhkhO3CO5E"
    "rU2rVdUr89wKpNXbBODFKRtgxUT70YpmJ46VVaqdAhOZD9EUUn4YaeLaS8AjSF/h7UkjOibNc4qV"
    "DiPP+rkehFWM66PVnP1Msh93tc+taIfCEYVMxjh8zNbFuoc7fzvvrFILLe7ifvEIUqSVIC/AzplM"
    "/Jxw7buXFeGP1qVCBEHq391d/9RAfaZ12zkwFsl+IKwE/OZxW8AHa9i1p4GO0YSNuczzEm4="
)

der_bytes = base64.b64decode(ca_b64)
assert hashlib.sha256(der_bytes).hexdigest() == \
    "d26d2d0231b7c39f92cc738512ba54103519e4405d68b5bd703e9788ca8ecf31", \
    "SHA-256 сертификата не совпал — base64 повреждён"

# Ряды по 12 байт: компактно и читаемо.
rows = []
for i in range(0, len(der_bytes), 12):
    rows.append("    " + ", ".join(f"0x{b:02x}" for b in der_bytes[i:i + 12]) + ",")
der_array = "\n".join(rows)

targets = list(Path(".").rglob("profile_network_context_service.cc"))
assert targets, "profile_network_context_service.cc не найден — патч Минцифры некуда применить"

for target in targets:
    content = target.read_text(encoding="utf-8")

    if "kRussianTrustedRootCaDer" in content:
        print(f"[custom] Уже пропатчено, пропускаю: {target}")
        continue

    anchor_def = "bool IsValidDNSConstraint(std::string_view possible_dns_constraint) {"
    anchor_use = ("auto additional_certificates =\n"
                  "      cert_verifier::mojom::AdditionalCertificates::New();")

    # Громкий отказ лучше тихой сборки без корневого сертификата.
    assert anchor_def in content, \
        f"[custom] Анкер определения не найден в {target} — версия Chromium изменилась"
    assert anchor_use in content, \
        f"[custom] Анкер вставки не найден в {target} — версия Chromium изменилась"

    def_code = f"""
#if BUILDFLAG(IS_ANDROID)
constexpr uint8_t kRussianTrustedRootCaDer[] = {{
{der_array}
}};
#endif
"""
    content = content.replace(anchor_def, def_code + "\n" + anchor_def)

    use_code = """
#if BUILDFLAG(IS_ANDROID)
  // BEGIN Russian Trusted Root CA (scoped trust)
  auto russian_trusted_root =
      cert_verifier::mojom::CertWithConstraints::New();
  russian_trusted_root->certificate = std::vector<uint8_t>(
      kRussianTrustedRootCaDer,
      kRussianTrustedRootCaDer + sizeof(kRussianTrustedRootCaDer));
  // Ведущая точка = только поддомены и сам домен этой зоны.
  russian_trusted_root->permitted_dns_names = {".ru", ".xn--p1ai", ".su"};
  additional_certificates->trust_anchors_with_additional_constraints.push_back(
      std::move(russian_trusted_root));
#endif  // BUILDFLAG(IS_ANDROID)
  // END Russian Trusted Root CA (scoped trust)
"""
    content = content.replace(anchor_use, anchor_use + "\n" + use_code)

    assert content.count("kRussianTrustedRootCaDer") >= 3, "[custom] Вставка не удалась"
    assert '".xn--p1ai"' in content, "[custom] Ограничение .рф не вставлено"

    target.write_text(content, encoding="utf-8")
    print(f"[custom] Патч Минцифры применён к {target} (.ru, .xn--p1ai, .su)")
EOF

echo "=== [custom] Исправление GN-зависимости bookmark_import_export_helper -> user_data_importer mojom ==="

python3 - << 'EOF'
from pathlib import Path

gn_files = list(Path(".").rglob("chrome/browser/bookmarks/android/BUILD.gn"))
for gn_file in gn_files:
    content = gn_file.read_text(encoding="utf-8")
    if "//components/user_data_importer/mojom" in content:
        print(f"[custom] mojom dependency already in {gn_file}")
        continue
    target = '"//chrome/browser/bookmarks",'
    if target in content:
        content = content.replace(target, target + '\n    "//components/user_data_importer/mojom",')
        gn_file.write_text(content, encoding="utf-8")
        print(f"[custom] Добавлена зависимость //components/user_data_importer/mojom в {gn_file}")
    else:
        print(f"[custom] Предупреждение: {target} не найден в {gn_file}")
EOF

echo "=== [custom] Исправление закрытия попапа расширений при выборе файла (Issue #252) ==="

python3 - << 'EOF'
import re
from pathlib import Path

# 1. Патчим ExtensionActionPopup.java
popup_files = list(Path(".").rglob("ExtensionActionPopup.java"))
assert popup_files, "ExtensionActionPopup.java не найден"

for popup_file in popup_files:
    content = popup_file.read_text(encoding="utf-8")
    if "mIsIntentActive" in content:
        print(f"[custom] ExtensionActionPopup.java уже пропатчен: {popup_file}")
        continue

    # Добавляем поле mIsIntentActive и геттер
    content, n1 = re.subn(
        r'(private\s+final\s+ContentView\s+mContentView;)',
        r'\1\n    private boolean mIsIntentActive;\n\n    public boolean isIntentActive() {\n        return mIsIntentActive;\n    }',
        content
    )

    # Создаём mPopupWindowAndroid до setDelegates и передаём его в webContents.setDelegates
    replacement_window = '''mPopupWindowAndroid =
                new ActivityWindowAndroid(
                        activity,
                        /* listenToActivityState= */ false,
                        NullUtil.assumeNonNull(windowAndroid.getIntentRequestTracker()),
                        /* insetObserver= */ null,
                        /* occlusionTrackingAllowed= */ true) {
                    @Override
                    public @Nullable ModalDialogManager getModalDialogManager() {
                        return windowAndroid.getModalDialogManager();
                    }

                    @Override
                    public int showCancelableIntent(
                            android.content.Intent intent,
                            @Nullable IntentCallback callback,
                            @Nullable Integer errorId) {
                        mIsIntentActive = true;
                        return super.showCancelableIntent(
                                intent,
                                (resultCode, results) -> {
                                    mIsIntentActive = false;
                                    if (callback != null) {
                                        callback.onIntentCompleted(resultCode, results);
                                    }
                                    if (!mPopupWindow.isShowing()) {
                                        mPopupWindow.show();
                                    }
                                },
                                errorId);
                    }

                    @Override
                    public int showCancelableIntent(
                            android.app.PendingIntent intent,
                            @Nullable IntentCallback callback,
                            @Nullable Integer errorId) {
                        mIsIntentActive = true;
                        return super.showCancelableIntent(
                                intent,
                                (resultCode, results) -> {
                                    mIsIntentActive = false;
                                    if (callback != null) {
                                        callback.onIntentCompleted(resultCode, results);
                                    }
                                    if (!mPopupWindow.isShowing()) {
                                        mPopupWindow.show();
                                    }
                                },
                                errorId);
                    }

                    @Override
                    public int showCancelableIntent(
                            org.chromium.base.Callback<Integer> intentTrigger,
                            @Nullable IntentCallback callback,
                            @Nullable Integer errorId) {
                        mIsIntentActive = true;
                        return super.showCancelableIntent(
                                intentTrigger,
                                (resultCode, results) -> {
                                    mIsIntentActive = false;
                                    if (callback != null) {
                                        callback.onIntentCompleted(resultCode, results);
                                    }
                                    if (!mPopupWindow.isShowing()) {
                                        mPopupWindow.show();
                                    }
                                },
                                errorId);
                    }
                };

        { View decor = activity.getWindow().getDecorView(); webContents.setSize(decor.getWidth(), decor.getHeight()); }

        webContents.setDelegates(
                VersionInfo.getProductVersion(),
                ViewAndroidDelegate.createBasicDelegate(mContentView),
                mContentView,
                mPopupWindowAndroid,
                WebContents.createDefaultInternalsHolder());'''

    pattern_window = r'''webContents\.setDelegates\(\s*VersionInfo\.getProductVersion\(\),\s*ViewAndroidDelegate\.createBasicDelegate\(mContentView\),\s*mContentView,\s*windowAndroid,\s*WebContents\.createDefaultInternalsHolder\(\)\);(\s*\{[^\}]+\}\s*)?mPopupWindowAndroid\s*=\s*new\s+ActivityWindowAndroid\s*\([^;]+?getModalDialogManager\(\)\s*\{[^}]+?\}[^;]*?\};'''
    content, n2 = re.subn(pattern_window, replacement_window, content, flags=re.DOTALL)

    # Блокируем закрытие AnchoredPopupWindow при активном выборе файла
    pattern_popup = r'mPopupWindow\s*=\s*new\s+AnchoredPopupWindow\s*\([^;]+?new\s+ViewRectProvider\(anchorView\)\);'
    replacement_popup = '''mPopupWindow =
                new AnchoredPopupWindow(
                        activity,
                        activity.getWindow().getDecorView(),
                        new ColorDrawable(Color.WHITE),
                        mThinWebView.getView(),
                        new ViewRectProvider(anchorView)) {
                    @Override
                    public void dismiss() {
                        if (mIsIntentActive) {
                            return;
                        }
                        super.dismiss();
                    }
                };'''

    content, n3 = re.subn(pattern_popup, replacement_popup, content, flags=re.DOTALL)

    # Защита в mCurrentTabObserver
    pattern_tab_observer = r'mCurrentTabObserver\s*=\s*tab\s*->\s*\{[^;]+?mPopupWindow\.dismiss\(\);\s*\}\s*\};'
    replacement_tab_observer = '''mCurrentTabObserver =
                tab -> {
                    if (mPopupWindow.isShowing() && !mIsIntentActive) {
                        mPopupWindow.dismiss();
                    }
                };'''
    content, n4 = re.subn(pattern_tab_observer, replacement_tab_observer, content, flags=re.DOTALL)

    # В destroy() сбрасываем флаг
    pattern_destroy = r'(public\s+void\s+destroy\(\)\s*\{[^}]+?removeObserver\(mCurrentTabObserver\);)'
    content, n5 = re.subn(pattern_destroy, r'\1\n        mIsIntentActive = false;', content, flags=re.DOTALL)

    assert n1 == 1 and n2 == 1 and n3 == 1 and n4 == 1 and n5 == 1, \
        f"[custom] Ошибка наложения патча на {popup_file}: n1={n1}, n2={n2}, n3={n3}, n4={n4}, n5={n5}"

    popup_file.write_text(content, encoding="utf-8")
    print(f"[custom] Патч сохранения попапа расширений при выборе файла применён к {popup_file}")

# 2. Патчим ExtensionActionListMediator.java (предотвращаем уничтожение попапа при onDismiss во время выбора файла)
mediator_files = list(Path(".").rglob("ExtensionActionListMediator.java"))
assert mediator_files, "ExtensionActionListMediator.java не найден"

for mediator_file in mediator_files:
    content = mediator_file.read_text(encoding="utf-8")
    if "isIntentActive" in content:
        print(f"[custom] ExtensionActionListMediator.java уже пропатчен: {mediator_file}")
        continue

    pattern_mediator = r'(ActionState\.PopupActive\s+actionState\s*=\s*\(ActionState\.PopupActive\)\s*mActionState;)'
    replacement_mediator = r'''\1
        if (actionState.getPopup().isIntentActive()) {
            return;
        }'''

    content, nm = re.subn(pattern_mediator, replacement_mediator, content)
    assert nm == 1, f"[custom] Не удалось вставить проверку isIntentActive в {mediator_file}"

    mediator_file.write_text(content, encoding="utf-8")
    print(f"[custom] Патч ExtensionActionListMediator применён к {mediator_file}")
EOF

echo "=== [custom] Готово ==="
