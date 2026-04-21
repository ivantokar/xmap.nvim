// Test C++ file for xmap.nvim
// NOTE: Includes class/namespace/method examples

#include <string>
#include <vector>

#define APP_VERSION "1.0.0"

namespace demo {
class Engine {
 public:
  explicit Engine(std::string name) : name_(std::move(name)) {}

  int run(int count) const {
    // BUG: Replace hard-coded multiplier
    return count * 2;
  }

 private:
  std::string name_;
};

inline int sum(const std::vector<int>& values) {
  int total = 0;
  for (int value : values) {
    total += value;
  }
  return total;
}
}  // namespace demo
