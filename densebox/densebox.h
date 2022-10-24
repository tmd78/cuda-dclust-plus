#ifndef DENSEBOX_H
#define DENSEBOX_H

#include <cmath>
#include <iostream>
#include <vector>

#include "densebox_grid.h"

class Densebox {
  private:
    DenseboxGrid grid;
    bool createGrid(std::vector<std::vector<double>> &data, int dimensions, double epsilon);
  
  public:
    void cluster();
};

#endif