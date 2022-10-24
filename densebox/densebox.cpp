#include "densebox.h"

using std::cout;
using std::vector;

void Densebox::cluster() {
  //
}

// data is pass-by-reference so a copy is not made; it is not modified.
bool Densebox::createGrid(vector<vector<double>> &data, int dimensions, double epsilon) {
  if (epsilon < 0) {
    cout << "[Densebox] epsilon cannot be negative" << '\n';
    return false;
  }
  
  // Calculate length of one cell side.
  double cellLength = epsilon / (2.0 * sqrt(2.0));

  // Calculate min/max bounds for each dimension.
  for (int d = 0; d < dimensions; d++) {
    double min = data[d][0];
    double max = data[d][0];

    for (auto value : data[d]) {
      if (value < min) {
        min = value;
      }

      if (value > max) {
        max = value;
      }
    }

    // Record min/max values.
    // The additional cell length prevents us from missing edge points.
    grid.minBounds.push_back(min - cellLength);
    grid.maxBounds.push_back(max + cellLength);
  }
  
  // Calculate grid dimensions--number of cells in each dimension.
  for (int d = 0; d < dimensions; d++) {
    int cellCount = ceil((grid.maxBounds[d] - grid.minBounds[d]) / cellLength);
    grid.dimensions.push_back(cellCount);
  }

  // Set remaining grid values.
  grid.cellLength = cellLength;

  return true;
}