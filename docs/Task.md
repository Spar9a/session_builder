## Session Builder
### Data specification

Let's imagine there is data about usage of different IDEs with the following structure:

    - user_id — a user's anonymized identifier;
    - event_id - identifier of an event that happened inside an IDE. Each event corresponds
        to action either of a user or an IDE itself. For the sake of simplicity we assume that an
        event is a user action if event_id in ('a' ', 'b', 'c');
    - timestamp;
    - product_code - shortened name of an IDE


A new batch of raw data becomes available each day and is related to **five** past days maximum.

---

### Task

Suggest a solution for computation of a user session identifier. It has **user_id#product_code#timestamp** format where **timestamp** corresponds to the beginning of
a session. The identifier can be assigned to an event regardless of its type.

A session always starts with a user's event (not an IDE's) and breaks if there are no user
actions for five minutes. Sessions need to be extended if new related data was acquired (for
example, today we received data from three days ago).

It's up to you what technologies to use and how detailed the design and implementation should
be.