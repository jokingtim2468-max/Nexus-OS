import QtQml
// PipeWire needs objects "tracked" before their properties are live; on Windows they always are.
QtObject { property list<QtObject> objects; property var objectsVar }
