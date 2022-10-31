#include "densebox.h"

using std::cout;
using std::map;
using std::vector;

void Densebox::cluster(vector<vector<double>> &data)
{
  // FIXME: Create grid.

  // Assign points to cells.
  #pragma region

  // Key: Point index.
  // Value: Linear ID.
  map<int, int> linearIds;

  int cellIndex;
  int dataSize = data[0].size();
  int linearId;
  int multiplier;

  #pragma omp parallel for private(cellIndex, linearId, multiplier)
  for (int i = 0; i < dataSize; i++)
  {
    linearId = 0;
    multiplier = 1;

    for (int d = 0; d < DIMS; d++)
    {
      // Get cell index for point i.
      cellIndex = floor((data[d][i] - grid_.minBounds[d]) / grid_.cellLength);

      // Modify linear ID using cell index.
      linearId += cellIndex * multiplier;
      multiplier *= dataSize;
    }

    linearIds[i] = linearId;
  }
  
  #pragma endregion

  // FIXME: Finish implementation.
}

// data is pass-by-reference so a copy is not made; it is not modified.
bool Densebox::createGrid(vector<vector<double>> &data, double epsilon)
{
  if (epsilon < 0)
  {
    cout << "[Densebox] epsilon cannot be negative" << '\n';
    return false;
  }

  // Calculate length of one cell side.
  double cellLength = epsilon / (2.0 * sqrt(2.0));

  // Calculate min/max bounds for each dimension.
  for (int d = 0; d < DIMS; d++)
  {
    double min = data[d][0];
    double max = data[d][0];

    for (auto value : data[d])
    {
      if (value < min)
      {
        min = value;
      }

      if (value > max)
      {
        max = value;
      }
    }

    // Record min/max values.
    // The additional cell length prevents us from missing edge points.
    grid_.minBounds.push_back(min - cellLength);
    grid_.maxBounds.push_back(max + cellLength);
  }

  // Calculate grid dimensions--number of cells in each dimension.
  for (int d = 0; d < DIMS; d++)
  {
    int cellCount = ceil((grid_.maxBounds[d] - grid_.minBounds[d]) / cellLength);
    grid_.dimensions.push_back(cellCount);
  }

  // Set remaining grid values.
  grid_.cellLength = cellLength;

  return true;
}