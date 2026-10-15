"""Bitsquid resource name hashing (MurmurHash64A, seed 0)."""

M64 = 0xFFFFFFFFFFFFFFFF


def murmur64(s, seed=0):
    data = s.encode() if isinstance(s, str) else s
    m = 0xC6A4A7935BD1E995
    r = 47
    h = (seed ^ (len(data) * m)) & M64
    n = len(data) // 8 * 8
    for i in range(0, n, 8):
        k = int.from_bytes(data[i:i + 8], "little")
        k = (k * m) & M64
        k ^= k >> r
        k = (k * m) & M64
        h ^= k
        h = (h * m) & M64
    tail = data[n:]
    if tail:
        h ^= int.from_bytes(tail, "little")
        h = (h * m) & M64
    h ^= h >> r
    h = (h * m) & M64
    h ^= h >> r
    return h


TYPE_NAMES = """
animation animation_curves apb bik bones crypto data entity flow font ivf
level lua material mod mouse_cursor network_config package particles
physics_properties render_config rt_pipeline scene shader shader_library
shader_library_group shading_environment shading_environment_mapping
slug slug_album sound_environment state_machine strings surface_properties
texture timpani_bank timpani_master tome unit vector_field wav wwise_bank
wwise_dep wwise_metadata wwise_stream config script_flow_nodes
""".split()

TYPES = {murmur64(t): t for t in TYPE_NAMES}

_names = {}


def add_names(names):
    for n in names:
        _names[murmur64(n)] = n


def name_of(h):
    return _names.get(h, f"{h:016x}")


def type_of(h):
    return TYPES.get(h, f"{h:016x}")
