#!/usr/bin/env bash
# Кастомные патчи Titanium (накладываются ПОСЛЕ upstream patch.sh).
# Минцифры root CA, ограниченный зонами .ru / .xn--p1ai (.рф) / .su.
#
# ВАЖНО: этот файл отдельный, чтобы patch.sh можно было обновлять копированием
# из upstream без повторного вклеивания блока Минцифры.

# Скрипт сорсится из build.sh: ошибка здесь должна останавливать сборку,
# а не оставлять APK без корневого сертификата.
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

echo "=== [custom] Готово ==="
