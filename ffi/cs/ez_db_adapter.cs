using System;
using System.IO;
using System.Collections.Concurrent;
using System.Collections.Generic;

namespace EzDbEngine
{
    public sealed class EzDbAdapter
    {
        private static readonly Lazy<EzDbAdapter> _lazy = new Lazy<EzDbAdapter>(() => new EzDbAdapter());
        public static EzDbAdapter Instance => _lazy.Value;

        private readonly EzDBEngine _engine;
        private readonly ConcurrentDictionary<string, ulong> _handles;

        private EzDbAdapter()
        {
            _engine = EzDBEngine.Instance;
            _handles = new ConcurrentDictionary<string, ulong>();
        }

        public ulong GetHandle(string tableName)
        {
            string filePath = Path.Combine("data", $"{tableName}.ebf");
            return _handles.GetOrAdd(filePath, path => _engine.Use(path));
        }

        public ulong Insert(string tableName, Dictionary<string, string> data)
        {
            ulong h = GetHandle(tableName);
            var fdt = _engine.GetFdt(h);

            var values = new List<string>(fdt.Count);
            foreach (var f in fdt)
            {
                string name = f.GetName();
                values.Add(data.TryGetValue(name, out var val) ? val : "");
            }

            string csvPayload = string.Join(",", values);
            int st = _engine.Append(h, csvPayload, 1, ",");
            if (st != 0)
            {
                throw new InvalidOperationException($"Atomic append failed on table: {tableName} | Detail: {_engine.GetDetailedError(st)}");
            }
            _engine.Commit(h);
            return _engine.GetRecordCount(h);
        }
    }
}