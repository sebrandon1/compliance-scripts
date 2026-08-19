function statusMatchesFilter(status, filter) {
  return filter === 'all' ||
    (filter === 'pass-vanilla' && status.indexOf('pass-vanilla') !== -1) ||
    (filter !== 'pass-vanilla' && status === filter);
}
