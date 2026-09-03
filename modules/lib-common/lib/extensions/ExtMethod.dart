

extension ApplyNullable<T> on T? {
  T? apply(void Function(T value) block) {
    if (this != null) {
      block(this as T);
    }

    return this;
  }
}