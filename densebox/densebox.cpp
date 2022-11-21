#include "densebox.hpp"

using std::cout;
using std::map;
using std::vector;

bool Densebox::cluster(vector<vector<double>> &data, double epsilon, int minPts)
{
  // Validate arguments.
  if (epsilon < 0)
  {
    cout << "[Densebox] epsilon cannot be negative" << '\n';
    return false;
  }

  // Create grid.
  createGrid(data, epsilon);

  // region Assign points to cells.
  //--------------------------------------------------------------------------------
  int dCellIndex;
  uint64_t dataSize = data[0].size();
  uint64_t linearId;
  uint64_t multiplier;

  vector<Point> points;
  points.resize(dataSize);

#pragma omp parallel for private(cellIndex, linearId, multiplier)
  for (uint64_t i = 0; i < dataSize; i++)
  {
    linearId = 0;
    multiplier = 1;

    for (int d = 0; d < DIMS; d++)
    {
      // Get point i's cell index in dimension d.
      dCellIndex = floor((data[d][i] - grid_.minBounds[d]) / grid_.cellLength);

      // Calculate linear ID.
      linearId += dCellIndex * multiplier;

      // Modify multiplier for next dimension.
      multiplier *= grid_.dimensions[d];
    }

    points[i].index = i;
    points[i].linearId = linearId;
  }
  //--------------------------------------------------------------------------------
  // endregion Assign points to cells.

  // Sort points by linear ID in ascending order.
  sort(points.begin(), points.end(), comparePoints);

  // Find dense boxes.
  vector<uint64_t> denseBoxLinearIds;
  findDenseBoxes(denseBoxLinearIds, points, dataSize, minPts);

  UnionFind disjointSets = UnionFind(denseBoxLinearIds.size());

  for (int i = 1; i < denseBoxLinearIds.size(); i++)
  {
    // FIXME: Get x and y coordinates of current dense box.
  }

  // region Assign points to dense boxes (again?).
  //--------------------------------------------------------------------------------
  vector<Cell> denseBoxes;
  denseBoxes.resize(denseBoxLinearIds.size());

  uint64_t currentLinearId;
  vector<Point>::iterator low;

#pragma omp parallel for private(currentLinearId, low)
  for (uint64_t i = 0; i < denseBoxes.size(); i++)
  {
    currentLinearId = denseBoxLinearIds[i];
    denseBoxes[i].linearId = currentLinearId;

    // Note that points is sorted by linearId.
    // Find first index in points that belongs to dense box i.
    Point value = {.linearId = currentLinearId};
    low = std::lower_bound(points.begin(), points.end(), value);
    uint64_t currentPointIndex = std::distance(points.begin(), low);

    while (points[currentPointIndex].linearId == currentLinearId)
    {
      denseBoxes[i].pointIndices.push_back(currentPointIndex);
      currentPointIndex += 1;
    }
  }
  //--------------------------------------------------------------------------------
  // endregion Assign points to dense boxes.

  return true;
}

bool comparePoints(const Point &a, const Point &b)
{
  return a.linearId < b.linearId;
}

// data is pass-by-reference so a copy is not made; it is not modified.
bool Densebox::createGrid(vector<vector<double>> &data, double epsilon)
{
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

void findDenseBoxes(vector<uint64_t> &denseBoxLinearIds, vector<Point> &points, uint64_t dataSize, int minPts)
{
  // Index of cell being processed.
  uint64_t current = points[0].linearId;
  // Number of points in the current cell.
  uint64_t density = 1;

  for (uint64_t i = 1; i < dataSize; i++)
  {
    if (points[i].linearId == current)
    {
      density += 1;
    }
    else
    {
      // Check if the current cell is a dense box.
      if (density >= minPts)
      {
        denseBoxLinearIds.push_back(current);
      }

      current = points[i].linearId;
      density = 1;
    }
  }

  // Check if the last cell is a dense box.
  if (density >= minPts)
  {
    denseBoxLinearIds.push_back(current);
  }
}