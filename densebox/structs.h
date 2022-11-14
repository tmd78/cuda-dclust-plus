#ifndef STRUCTS_H
#define STRUCTS_H

#include <cstdint>

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
  uint64_t linearId;

  // Overload < operator.
  // bool operator<(const Point &b) const
  // {
  //   return linearId < b.linearId;
  // }
};

#endif