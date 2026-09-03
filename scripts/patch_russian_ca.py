#!/usr/bin/env python3
"""
Скрипт встраивания сертификата Минцифры (Russian Trusted Root CA)
с ограничением области действия доменами .ru, .xn--p1ai (.рф) и .su
для Titanium Browser (по аналогии с Ruthenium Browser).
"""

import sys
import base64
import hashlib
from pathlib import Path

# Официальный PEM корневого сертификата Минцифры (Russian Trusted Root CA)
RUSSIAN_CA_PEM = """-----BEGIN CERTIFICATE-----
MIIFwjCCA6qgAwIBAgICEAAwDQYJKoZIhvcNAQELBQAwcDELMAkGA1UEBhMCUlUx
PzA9BgNVBAoMNlRoZSBNaW5pc3RyeSBvZiBEaWdpdGFsIERldmVsb3BtZW50IGFu
ZCBDb21tdW5pY2F0aW9uczEgMB4GA1UEAwwXUnVzc2lhbiBUcnVzdGVkIFJvb3Qg
Q0EwHhcNMjIwMzAxMjEwNDE1WhcNMzIwMjI3MjEwNDE1WjBwMQswCQYDVQQGEwJS
VTE/MD0GA1UECgw2VGhlIE1pbmlzdHJ5IG9mIERpZ2l0YWwgRGV2ZWxvcG1lbnQg
YW5kIENvbW11bmljYXRpb25zMSAwHgYDVQQDDBdSdXNzaWFuIFRydXN0ZWQgUm9v
dCBDQTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAMfFOZ8pUAL3+r2n
qqE0Zp52selXsKGFYoG0GM5bwz1bSLtCt+AZQMhkWQheI3poZAToYJu69pHLKS6Q
XBiwBC1cvzYmUYKMYZC7jE5YhEU2bSL0mX7NaMxMDmH2/NwuOVRj8OImVa5s1F4U
zn4Kv3PFlDBjjSjXKVY9kmjUBsXQrIHeaqmUIsPIlNWUnimXS0I0abExqkbdrXbX
YwCOXhOO2pDUx3ckmJlCMUGacUTnylyQW2VsJIyIGA8V0xzdaeUXg0VZ6ZmNUr5Y
Ber/EAOLPb8NYpsAhJe2mXjMB/J9HNsoFMBFJ0lLOT/+dQvjbdRZoOT8eqJpWnVD
U+QL/qEZnz57N88OWM3rabJkRNdU/Z7x5SFIM9FrqtN8xewsiBWBI0K6XFuOBOTD
4V08o4TzJ8+Ccq5XlCUW2L48pZNCYuBDfBh7FxkB7qDgGDiaftEkZZfApRg2E+M9
G8wkNKTPLDc4wH0FDTijhgxR3Y4PiS1HL2Zhw7bD3CbslmEGgfnnZojNkJtcLeBH
BLa52/dSwNU4WWLubaYSiAmA9IUMX1/RpfpxOxd4Ykmhz97oFbUaDJFipIggx5sX
ePAlkTdWnv+RWBxlJwMQ25oEHmRguNYf4Zr/Rxr9cS93Y+mdXIZaBEE0KS2iLRqa
OiWBki9IMQU4phqPOBAaG7A+eP8PAgMBAAGjZjBkMB0GA1UdDgQWBBTh0YHlzlpf
BKrS6badZrHF+qwshzAfBgNVHSMEGDAWgBTh0YHlzlpfBKrS6badZrHF+qwshzAS
BgNVHRMBAf8ECDAGAQH/AgEEMA4GA1UdDwEB/wQEAwIBhjANBgkqhkiG9w0BAQsF
AAOCAgEAALIY1wkilt/urfEVM5vKzr6utOeDWCUczmWX/RX4ljpRdgF+5fAIS4vH
tmXkqpSCOVeWUrJV9QvZn6L227ZwuE15cWi8DCDal3Ue90WgAJJZMfTshN4OI8cq
W9E4EG9wglbEtMnObHlms8F3CHmrw3k6KmUkWGoa+/ENmcVl68u/cMRl1JbW2bM+
/3A+SAg2c6iPDlehczKx2oa95QW0SkPPWGuNA/CE8CpyANIhu9XFrj3RQ3EqeRcS
AQQod1RNuHpfETLU/A2gMmvn/w/sx7TB3W5BPs6rprOA37tutPq9u6FTZOcG1Oqj
C/B7yTqgI7rbyvox7DEXoX7rIiEqyNNUguTk/u3SZ4VXE2kmxdmSh3TQvybfbnXV
4JbCZVaqiZraqc7oZMnRoWrXRG3ztbnbes/9qhRGI7PqXqeKJBztxRTEVj8ONs1d
WN5szTwaPIvhkhO3CO5ErU2rVdUr89wKpNXbBODFKRtgxUT70YpmJ46VVaqdAhOZ
D9EUUn4YaeLaS8AjSF/h7UkjOibNc4qVDiPP+rkehFWM66PVnP1Msh93tc+taIfC
EYVMxjh8zNbFuoc7fzvvrFILLe7ifvEIUqSVIC/AzplM/Jxw7buXFeGP1qVCBEHq
391d/9RAfaZ12zkwFsl+IKwE/OZxW8AHa9i1p4GO0YSNuczzEm4=
-----END CERTIFICATE-----"""

# Корректный SHA-256 DER байтов сертификата
EXPECTED_DER_SHA256 = "b3ace28381eaa2a64fa506f001a8f389befc53c9b50a2e10236ecdb757dac670"

DEFINITION_ANCHOR = "bool IsValidDNSConstraint(std::string_view possible_dns_constraint) {"
USE_ANCHOR = "auto additional_certificates =\n      cert_verifier::mojom::AdditionalCertificates::New();"

DEFINITION_BEGIN = "// BEGIN Russian Trusted Root CA (Android-only, DNS-constrained)"
DEFINITION_END = "// END Russian Trusted Root CA (Android-only, DNS-constrained)"
USE_BEGIN = "  // BEGIN Russian Trusted Root CA scoped trust"
USE_END = "  // END Russian Trusted Root CA scoped trust"

def pem_to_der(pem: str) -> bytes:
    # Очищаем от заголовков и любых пробельных символов
    lines = [
        line.strip()
        for line in pem.strip().splitlines()
        if not line.startswith("-----")
    ]
    base64_str = "".join(lines)
    der = base64.b64decode(base64_str)
    
    actual_hash = hashlib.sha256(der).hexdigest()
    if actual_hash.lower() != EXPECTED_DER_SHA256.lower():
        raise ValueError(
            f"Хэш сертификата не совпадает! Ожидался {EXPECTED_DER_SHA256}, получен {actual_hash}"
        )
    return der

def format_der_array(der: bytes) -> str:
    lines = []
    for offset in range(0, len(der), 12):
        chunk = der[offset : offset + 12]
        lines.append("    " + ", ".join(f"0x{byte:02x}" for byte in chunk) + ",")
    return "\n".join(lines)

def build_definition_block(der: bytes) -> str:
    return f"""{DEFINITION_BEGIN}
#if BUILDFLAG(IS_ANDROID)
// Source: https://gu-st.ru/content/lending/russian_trusted_root_ca_pem.crt
// DER SHA-256: {EXPECTED_DER_SHA256}
constexpr uint8_t kRussianTrustedRootCaDer[] = {{
{format_der_array(der)}
}};
#endif  // BUILDFLAG(IS_ANDROID)
{DEFINITION_END}

"""

def build_use_block() -> str:
    return f"""
{USE_BEGIN}
#if BUILDFLAG(IS_ANDROID)
  auto russian_trusted_root =
      cert_verifier::mojom::CertWithConstraints::New();
  russian_trusted_root->certificate = std::vector<uint8_t>(
      kRussianTrustedRootCaDer,
      kRussianTrustedRootCaDer + sizeof(kRussianTrustedRootCaDer));
  // Ограничение области доверия: только поддомены .ru, .xn--p1ai (.рф) и .su
  russian_trusted_root->permitted_dns_names = {{".ru", ".xn--p1ai", ".su"}};
  additional_certificates->trust_anchors_with_additional_constraints.push_back(
      std::move(russian_trusted_root));
#endif  // BUILDFLAG(IS_ANDROID)
{USE_END}"""

def patch_file(file_path: Path):
    content = file_path.read_text(encoding="utf-8")
    
    if DEFINITION_BEGIN in content and USE_BEGIN in content:
        print(f"Файл {file_path} уже пропатчен.")
        return

    der = pem_to_der(RUSSIAN_CA_PEM)

    # 1. Вставка массива байт сертификата
    if DEFINITION_ANCHOR in content:
        content = content.replace(DEFINITION_ANCHOR, build_definition_block(der) + DEFINITION_ANCHOR, 1)
    else:
        content = build_definition_block(der) + content

    # 2. Вставка привязки сертификата с ограничениями по доменам
    if USE_ANCHOR in content:
        content = content.replace(USE_ANCHOR, USE_ANCHOR + build_use_block(), 1)
    else:
        raise ValueError("Не удалось найти якорь AdditionalCertificates в исходном файле")

    file_path.write_text(content, encoding="utf-8")
    print(f"Файл {file_path} успешно пропатчен.")

if __name__ == "__main__":
    target = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("chrome/browser/net/profile_network_context_service.cc")
    patch_file(target)
