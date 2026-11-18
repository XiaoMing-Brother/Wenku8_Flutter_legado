/// Local originals and virtual series share a reserved identity range.
const localBookIdStart = 0x60000000;
const bookSourceIdStart = 0x50000000;
const bookSourceIdEnd = 0x60000000;

/// Imported book list rows waiting for a readable source identity.
const pendingBookIdStart = 0x40000000;
const pendingBookIdEnd = 0x50000000;
bool isLocalBook(int id) => id >= localBookIdStart;
bool isBookSourceBook(int id) =>
    id >= bookSourceIdStart && id < bookSourceIdEnd;
