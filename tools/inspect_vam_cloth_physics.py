"""Read material-slot aliases and cloth geometry schema 1.0 after the wrap section.

Only data layout is decoded. No third-party simulation implementation is copied.
"""
from inspect_vam_clothing import Reader


def decode_tail(binary, tail_size):
    r = Reader(binary[-tail_size:])
    materials = []
    extra_wraps = []
    while r.stream.tell() < tail_size:
        marker = r.stream.getbuffer()[r.stream.tell()]
        if marker == len('MaterialOptions'):
            r.section('MaterialOptions')
            alias = r.string()
            slots = list(r.unpack('i'*r.count()))
            materials.append(dict(alias=alias, slots=slots))
        elif marker == len('DAZSkinWrap'):
            r.section('DAZSkinWrap'); name = r.string(); r.section('DAZSkinWrapStore')
            extra_wraps.append(dict(name=name, bindings=[r.unpack('iiiiffffff') for _ in range(r.count())]))
        else: break
    present, = r.unpack('?')
    physics = None
    if present:
        r.section('ClothGeometryData')
        def array(fmt): return [r.unpack(fmt) for _ in range(r.count())]
        def scalars(fmt): return [v[0] for v in array(fmt)]
        physics = dict(triangles=scalars('i'), points=array('fff'),
                       mesh_to_physics=scalars('i'), physics_to_mesh=scalars('i'))
        for field in ['distance_groups', 'bend_groups', 'nearby_groups']:
            physics[field] = [array('ii') for _ in range(r.count())]
        physics['neighbors'] = scalars('i')
        physics['neighbor_counts'] = scalars('i')
        physics['blend'] = scalars('f')
        physics['strength'] = scalars('f')
    assert r.stream.tell() == tail_size, 'Unknown trailing cloth schema: do not guess'
    return dict(materials=materials, physics=physics, extra_wraps=extra_wraps)
