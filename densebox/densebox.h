#ifndef DENSEBOX_H
#define DENSEBOX_H

#include <cmath>
#include <iostream>
#include <map>
#include <omp.h>
#include <vector>

#include "constants.h"
#include "densebox_grid.h"

class Densebox
{
private:
  DenseboxGrid grid_;
  bool createGrid(std::vector<std::vector<double>> &data, double epsilon);

public:
  void cluster(std::vector<std::vector<double>> &data);
};

#endif