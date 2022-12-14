#ifndef DENSEBOX_H
#define DENSEBOX_H

#include <algorithm>
#include <cmath>
#include <iostream>
#include <map>
#include <omp.h>
#include <vector>

#include "constants.hpp"
#include "structs.hpp"
#include "union-find.hpp"

class Densebox
{
private:
  Grid grid_;
  bool createGrid(std::vector<std::vector<double>> &data, double epsilon);

public:
  bool cluster(std::vector<std::vector<double>> &data, double epsilon, int minPts);
};

#endif