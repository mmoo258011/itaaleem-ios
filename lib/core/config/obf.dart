/// Host names and ids the app needs at runtime, stored XOR-encoded so they
/// don't sit as plain text in the binary's string table (`strings` /
/// a casual decompile). Not a secret store — nothing here is a secret; real
/// secrets never ship in the app.
class Obf {
  Obf._();

  static const _k = [0x5a, 0x13, 0xc7, 0x2e, 0x91, 0x44, 0xb, 0xe8];

  static String _d(List<int> b) => String.fromCharCodes([
    for (var i = 0; i < b.length; i++) b[i] ^ _k[i % _k.length],
  ]);

  static final String apiBase = _d(const [
    50,
    103,
    179,
    94,
    226,
    126,
    36,
    199,
    59,
    99,
    174,
    0,
    248,
    48,
    106,
    137,
    54,
    118,
    162,
    67,
    191,
    39,
    100,
    133,
    117,
    114,
    183,
    71,
    190,
    50,
    58,
  ]);
  static final String rootDomain = _d(const [
    51,
    103,
    166,
    79,
    253,
    33,
    110,
    133,
    116,
    112,
    168,
    67,
  ]);
  static final String apiHost = _d(const [
    59,
    99,
    174,
    0,
    248,
    48,
    106,
    137,
    54,
    118,
    162,
    67,
    191,
    39,
    100,
    133,
  ]);
  static final String appStoreId = _d(const [
    108,
    43,
    245,
    30,
    160,
    116,
    62,
    216,
    111,
    39,
  ]);
}
