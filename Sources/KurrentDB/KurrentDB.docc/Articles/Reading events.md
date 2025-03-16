# Reading events

There are two options for reading events from EventStoreDB. You can either: 1. Read from an individual stream, or 2. Read from the $all stream, which will return all events in the store.

Each event in EventStoreDB belongs to an individual stream. When reading events, pick the name of the stream from which you want to read the events and choose whether to read the stream forwards or backwards.

All events have a StreamPosition and a Position. StreamPosition is a big int (unsigned 64-bit integer) and represents the place of the event in the stream. Position is the event's logical position, and is represented by CommitPosition and a PreparePosition. Note that when reading events you will supply a different "position" depending on whether you are reading from an individual stream or the $all stream.

> Tips: 
> Check [connecting to EventStoreDB instructions](<doc:Getting-started>) to learn how to configure and use the client SDK.


