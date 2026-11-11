// The 4th map (Tutankhamun Galleries plan, page 4 of the official PDF): zones and
// highlight markers come from the PDF geometry. Routing: gem_nav.dart.
import 'package:flutter/material.dart';

import '../models/map_models.dart';

const _tutSize = Size(1389, 962);
Offset _tg(double x, double y) => Offset(x / _tutSize.width, y / _tutSize.height);

final GemMap tutankhamunMap = GemMap(
  id: 'tutankhamun',
  title: 'Tutankhamun Galleries',
  shortTitle: 'Tutankhamun',
  asset: 'assets/maps/dark/tutankhamun.svg',
  imageSize: _tutSize,
  entranceId: 'tg_entrance',
  places: [
    MapPlace(id: 'tg_entrance', name: 'Entrance', position: _tg(499.5, 409.4), category: PlaceCategory.entrance, glyph: PlaceGlyph.arrowUp, description: 'Entrance to the Tutankhamun Galleries.'),
    MapPlace(id: 'tg_exit', name: 'Exit', position: _tg(1258.6, 44.9), category: PlaceCategory.entrance, glyph: PlaceGlyph.arrowUp, description: 'Exit of the Tutankhamun Galleries, next to the reception area.'),
    MapPlace(id: 'tg_mask', name: 'Golden funerary mask', position: _tg(879.8, 527.9), category: PlaceCategory.attraction, number: '1', description: 'A highlight object marked on the official Tutankhamun Galleries plan.', chips: ['Funeral']),
    MapPlace(id: 'tg_throne', name: 'Golden throne', position: _tg(1207.1, 364.7), category: PlaceCategory.attraction, number: '2', description: 'A highlight object marked on the official Tutankhamun Galleries plan.', chips: ['Identity']),
    MapPlace(id: 'tg_coffin_a', name: 'Coffin 1', position: _tg(505.6, 704.9), category: PlaceCategory.attraction, number: '3', description: 'A highlight object marked on the official Tutankhamun Galleries plan.', chips: ['Funeral']),
    MapPlace(id: 'tg_coffin_b', name: 'Coffin 2', position: _tg(533.9, 691.5), category: PlaceCategory.attraction, number: '4', description: 'A highlight object marked on the official Tutankhamun Galleries plan.', chips: ['Funeral']),
    MapPlace(id: 'tg_coffin_c', name: 'Coffin 3', position: _tg(522.0, 653.5), category: PlaceCategory.attraction, number: '5', description: 'A highlight object marked on the official Tutankhamun Galleries plan.', chips: ['Funeral']),
    MapPlace(id: 'tg_shrine', name: 'Gilded shrine', position: _tg(288.6, 570.6), category: PlaceCategory.attraction, number: '6', description: 'A highlight object marked on the official Tutankhamun Galleries plan.', chips: ['Lifestyle']),
    MapPlace(id: 'tg_vase', name: 'Alabaster vase', position: _tg(455.0, 455.9), category: PlaceCategory.attraction, number: '7', description: 'A highlight object marked on the official Tutankhamun Galleries plan.', chips: ['Lifestyle']),
    MapPlace(id: 'tg_bowl', name: 'Stone bowl', position: _tg(1021.5, 218.1), category: PlaceCategory.attraction, number: '8', description: 'A highlight object marked on the official Tutankhamun Galleries plan.', chips: ['Discovery']),
    MapPlace(id: 'tg_boat', name: 'Model boat', position: _tg(42.9, 878.4), category: PlaceCategory.attraction, number: '9', description: 'A highlight object marked on the official Tutankhamun Galleries plan.', chips: ['Funeral (start)']),
  ],
);
