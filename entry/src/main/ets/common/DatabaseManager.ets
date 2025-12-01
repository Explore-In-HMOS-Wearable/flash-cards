import { relationalStore } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { JSON, util } from '@kit.ArkTS';
import WordData from '../models/WordData';


const DB_NAME: string = 'WordLists.db';
const DB_VERSION: number = 1;

const STORE_CONFIG: relationalStore.StoreConfig = {
  name: DB_NAME,
  securityLevel: relationalStore.SecurityLevel.S3,
  encrypt: false,
};

export interface Remaining {
  learnedCount: number,
  unlearnedCount: number
}

function getSQLCreateTableString(tableName: string) {
  return `CREATE TABLE IF NOT EXISTS ${tableName} (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    article TEXT,
    word TEXT NOT NULL,
    meaning TEXT,
    example TEXT,
    learned INTEGER DEFAULT 0
  )`
}

export interface WordListJson {
  version: string;
  header: Record<string, string>;
  data: WordData[];
}

export interface DatabaseManagerParam {
  databaseManager: DatabaseManager
}

export class DatabaseManager {
  private rdbStore?: relationalStore.RdbStore;
  private tableName: string = ''

  public close() {
    this.rdbStore?.close()
    this.rdbStore = undefined
  }

  async createStore(context: Context | undefined, tableName: string): Promise<void> {
    return new Promise<void>((resolve, reject) => {

      if (this.rdbStore && this.tableName === tableName) {
        resolve();
        return;
      }

      relationalStore.getRdbStore(context, STORE_CONFIG,
        async (err: BusinessError | undefined, store: relationalStore.RdbStore) => {
          if (err) {
            console.error(`Failed to get RdbStore. Code:${err.code}, message:${err.message}`);
            reject(err);
            return;
          }
          this.rdbStore = store
          this.tableName = tableName
          let storeVersion: number = store.version;

          try {
            const queryResult =
              await store.querySql(`SELECT name FROM sqlite_master WHERE type='table' AND name='${tableName}';`);
            const tableExists = queryResult.rowCount > 0;
            queryResult.close();

            if (!tableExists) {
              console.info(`Table '${tableName}' not found. Creating and importing...`);
              await store.execute(getSQLCreateTableString(tableName));
              await this.importFromJson(context, tableName)

              if (storeVersion === 0) {
                store.version = DB_VERSION;
              }
            } else {
              console.info(`Table '${tableName}' already exists. Skipping creation/import.`);
            }
          } catch (e) {
            const error = e as BusinessError;
            console.error(`Failed to handle table setup. Code:${error.code}, message:${error.message}`);
            reject(error);
            return;
          }

          resolve();
        });
    });
  }

  async insertWord(entry: WordData): Promise<void> {
    if (!this.rdbStore) {
      throw new Error('Database not initialized.');
    }

    const values: relationalStore.ValuesBucket = {
      article: entry.article,
      word: entry.word,
      meaning: entry.meaning,
      example: entry.example,
    };

    try {
      const rowId: number = await this.rdbStore.insert(this.tableName, values);
      console.info(`Inserted word "${entry.word}" (rowId=${rowId})`);
    } catch (error) {
      const err = error as BusinessError;
      console.error(`Failed to insert word. Code:${err.code}, message:${err.message}`);
    }
  }

  async importFromJson(context: Context | undefined, filename: string): Promise<void> {
    const rm = context?.resourceManager;
    if (!rm) {
      console.error('resourceManager is undefined');
      return;
    }

    try {
      const fileData = await rm.getRawFileContent(`rawfile/wordLists/${filename}.json`);
      const decoder = util.TextDecoder.create('utf-8');
      let text = decoder.decodeToString(fileData)

      console.info('jsonText: ' + text)
      const wl = JSON.parse(text) as WordListJson;

      if (!wl.data || !Array.isArray(wl.data)) {
        console.error(`JSON missing 'data' array`);
        return;
      }

      for (const entry of wl.data) {
        await this.insertWord(entry);
      }

      console.info(`Imported ${wl.data.length} words.`);
    } catch (e) {
      console.error('JSON import failed:', JSON.stringify(e));
    }
  }


  async getAllWords(): Promise<Array<WordData>> {
    if (!this.rdbStore) {
      throw new Error('Database not initialized.');
    }

    return new Promise<Array<WordData>>((resolve, reject) => {
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(this.tableName);

      this.rdbStore!.query(
        predicates,
        ['id', 'article', 'word', 'meaning', 'example', 'learned'],
        (err: BusinessError | undefined, resultSet: relationalStore.ResultSet) => {
          if (err) {
            console.error(`Query failed. Code:${err.code}, message:${err.message}`);
            reject(err);
            return;
          }

          const results: Array<WordData> = [];

          while (resultSet.goToNextRow()) {
            results.push(new WordData(
              resultSet.getLong(resultSet.getColumnIndex('id')),
              resultSet.getString(resultSet.getColumnIndex('article')),
              resultSet.getString(resultSet.getColumnIndex('word')),
              resultSet.getString(resultSet.getColumnIndex('meaning')),
              resultSet.getString(resultSet.getColumnIndex('example')),
              resultSet.getLong(resultSet.getColumnIndex('learned')) === 1
            )
            );
          }

          resultSet.close();
          resolve(results);
        }
      );
    });
  }

  async setLearnedById(id: number): Promise<void> {
    if (!this.rdbStore) {
      throw new Error('Database not initialized.');
    }

    const values: relationalStore.ValuesBucket = {
      learned: 1, // 1 for true
    };

    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(this.tableName);
    predicates.equalTo('id', id);

    try {
      const rowsAffected: number = await this.rdbStore.update(values, predicates);
      if (rowsAffected > 0) {
        console.info(`Updated word with id=${id} to learned=true. Rows affected: ${rowsAffected}`);
      } else {
        console.warn(`No word found with id=${id} to update.`);
      }
    } catch (error) {
      const err = error as BusinessError;
      console.error(`Failed to update word. Code:${err.code}, message:${err.message}`);
    }
  }

  async getRandomUnlearnedWord(requiredCount: number, excludedIds: number[] = []): Promise<WordData[] | null> {
    if (!this.rdbStore) {
      throw new Error('Database not initialized.');
    }

    const rdbStore = this.rdbStore;
    const tableName = this.tableName;

    // Convert excludedIds to a comma-separated string for the SQL 'NOT IN' clause
    const excludedIdsString = excludedIds.join(', ');

    return new Promise<WordData[] | null>((resolve, reject) => {

      // Step 1: Count the number of unlearned words, excluding the given IDs
      const countPredicates = new relationalStore.RdbPredicates(tableName);
      countPredicates.equalTo('learned', 0);

      // Add NOT IN clause if excludedIds is not empty
      if (excludedIds.length > 0) {
        countPredicates.notIn('id', excludedIds);
      }

      rdbStore.query(
        countPredicates,
        ['COUNT(*)'],
        (err: BusinessError | undefined, countResultSet: relationalStore.ResultSet) => {
          if (err) {
            console.error(`Query (Count) failed. Code:${err.code}, message:${err.message}`);
            reject(err);
            return;
          }

          let totalUnlearnedCount = 0;
          if (countResultSet.goToFirstRow()) {
            // countResultSet.getLong(0) is the COUNT(*) value
            totalUnlearnedCount = countResultSet.getLong(0);
          }
          countResultSet.close();

          if (totalUnlearnedCount === 0) {
            console.warn('No unlearned words found after exclusion.');
            resolve(null);
            return;
          }

          const N = Math.min(requiredCount, totalUnlearnedCount);
          if (N === 0) {
            resolve([]);
            return;
          }

          // Step 2: Generate N Unique Random Offsets based on the total remaining count
          const offsets = new Set<number>();
          while (offsets.size < N) {
            offsets.add(Math.floor(Math.random() * totalUnlearnedCount));
          }
          const offsetArray = Array.from(offsets);

          // Step 3: Fetch all N words concurrently (using a manual promise collector)
          const results: WordData[] = [];
          let completedQueries = 0;
          const totalQueries = N;

          for (const offset of offsetArray) {
            const wordPredicates = new relationalStore.RdbPredicates(tableName);
            wordPredicates.equalTo('learned', 0);

            // Add NOT IN clause to the fetching query as well
            if (excludedIds.length > 0) {
              wordPredicates.notIn('id', excludedIds);
            }

            wordPredicates.limitAs(1);
            wordPredicates.offsetAs(offset);

            rdbStore.query(
              wordPredicates,
              ['id', 'article', 'word', 'meaning', 'example', 'learned'],
              (err2: BusinessError | undefined, wordResultSet: relationalStore.ResultSet) => {
                if (err2) {
                  console.error(`Query (Word) failed. Code:${err2.code}, message:${err2.message}`);
                  reject(err2);
                  return;
                }

                if (wordResultSet.goToFirstRow()) {
                  results.push(new WordData(
                    wordResultSet.getLong(wordResultSet.getColumnIndex('id')),
                    wordResultSet.getString(wordResultSet.getColumnIndex('article')),
                    wordResultSet.getString(wordResultSet.getColumnIndex('word')),
                    wordResultSet.getString(wordResultSet.getColumnIndex('meaning')),
                    wordResultSet.getString(wordResultSet.getColumnIndex('example')),
                    wordResultSet.getLong(wordResultSet.getColumnIndex('learned')) === 1
                  ));
                }
                wordResultSet.close();

                completedQueries++;
                if (completedQueries === totalQueries) {
                  resolve(results);
                }
              }
            );
          }
        }
      );
    });
  }


  async getWordCounts(): Promise<Remaining> {
    if (!this.rdbStore) {
      throw new Error('Database not initialized.');
    }

    const rdbStore = this.rdbStore;
    const tableName = this.tableName;

    return new Promise<Remaining>((resolve, reject) => {
      let learnedCount: number = 0;
      let unlearnedCount: number = 0;
      let queriesCompleted: number = 0;
      const totalQueries: number = 2;

      const finishCheck = () => {
        queriesCompleted++;
        if (queriesCompleted === totalQueries) {
          resolve({ learnedCount, unlearnedCount });
        }
      };

      const learnedPredicates = new relationalStore.RdbPredicates(tableName);
      learnedPredicates.equalTo('learned', 1);

      rdbStore.query(
        learnedPredicates,
        ['COUNT(*)'],
        (err: BusinessError | undefined, resultSet: relationalStore.ResultSet) => {
          if (err) {
            console.error(`Query (Learned Count) failed. Code:${err.code}, message:${err.message}`);
            reject(err);
            return;
          }

          if (resultSet.goToFirstRow()) {
            learnedCount = resultSet.getLong(0);
          }
          resultSet.close();
          finishCheck();
        }
      );

      const unlearnedPredicates = new relationalStore.RdbPredicates(tableName);
      unlearnedPredicates.equalTo('learned', 0);

      rdbStore.query(
        unlearnedPredicates,
        ['COUNT(*)'],
        (err: BusinessError | undefined, resultSet: relationalStore.ResultSet) => {
          if (err) {
            console.error(`Query (Unlearned Count) failed. Code:${err.code}, message:${err.message}`);
            reject(err);
            return;
          }

          if (resultSet.goToFirstRow()) {
            unlearnedCount = resultSet.getLong(0);
          }
          resultSet.close();
          finishCheck();
        }
      );
    });
  }

  async setAllUnlearned(): Promise<void> {
    if (!this.rdbStore) {
      throw new Error('Database not initialized.');
    }

    const values: relationalStore.ValuesBucket = {
      learned: 0,
    };

    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(this.tableName);

    try {
      const rowsAffected: number = await this.rdbStore.update(values, predicates);
      console.info(`Reset learned status for table '${this.tableName}'. Rows affected: ${rowsAffected}`);
    } catch (error) {
      const err = error as BusinessError;
      console.error(`Failed to reset learned status. Code:${err.code}, message:${err.message}`);
    }
  }

}