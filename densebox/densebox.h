#ifndef DENSEBOX_H
#define DENSEBOX_H

#include <algorithm>
#include <cmath>
#include <iostream>
#include <map>
#include <omp.h>
#include <vector>

#include "constants.h"
#include "structs.h"

class Densebox
{
private:
  Grid grid_;
  bool createGrid(std::vector<std::vector<double>> &data, double epsilon);

public:
  void cluster(std::vector<std::vector<double>> &data, double epsilon, int minPts);
};

#endif