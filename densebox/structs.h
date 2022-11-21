#ifndef STRUCTS_H
#define STRUCTS_H

#include <cstdint>

struct Cell
{
  uint64_t linearId;
  vector<uint64_t> pointIndices;
};

struct Grid
{
  double cellLength;
  vector<int> dimensions;
  vector<double> minBounds;
  vector<double> maxBounds;
};

struct Point
{
  unsigned int index;

  // Index of the cell this point belongs to.
  uint64_t linearId;

  // Overload < operator; used by std::lower_bound().
  bool operator<(const Point &b) const
  {
    return linearId < b.linearId;
  }
};

#endif