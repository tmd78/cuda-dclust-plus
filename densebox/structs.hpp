#ifndef STRUCTS_H
#define STRUCTS_H

#include <cstdint>
#include <vector>

struct Cell
{
  uint64_t linearId;
  std::vector<uint64_t> pointIndices;
};

struct Grid
{
  double cellLength;
  std::vector<uint64_t> dimensions;
  std::vector<double> minBounds;
  std::vector<double> maxBounds;
};

struct MergePair
{
  uint64_t linearId1;
  uint64_t linearId2;
};

struct Point
{
  std::vector<uint64_t> cellCoordinates;
  uint64_t index;

  // Index of the cell this point belongs to.
  uint64_t linearId;

  // Overload < operator; used by std::lower_bound().
  bool operator<(const Point &b) const
  {
    return linearId < b.linearId;
  }
};

#endif