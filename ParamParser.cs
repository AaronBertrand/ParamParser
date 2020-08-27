using System;
using System.Data;
using System.Collections.Generic;
using System.Data.SqlClient;
using Microsoft.SqlServer.TransactSql.ScriptDom;

namespace AB.ParamParser
{

    class ParamParser
    {
        static void Main(string[] args)
        {
            var targetDB = "ParamParser_Demo"; // update this

            if (args.Length > 0 && !string.IsNullOrWhiteSpace(args[0]))
            {
              targetDB = args[0];
            }

            string connString = new SqlConnectionStringBuilder // update this
            {
              DataSource         = "127.0.0.1",   
              InitialCatalog     = "ParamParser_Central",     
              IntegratedSecurity = true
              //UserID           = "username",
              //Password         = "password"
            }.ToString();

            var object_id = 0;
            string definition;

            DataTable paramSet = new DataTable();
            paramSet.Columns.Add("object_id",     typeof(int));
            paramSet.Columns.Add("name",          typeof(string));
            paramSet.Columns.Add("default_value", typeof(string));

            using (SqlConnection conn = new SqlConnection(connString))
            {
                conn.Open();
                using (SqlCommand cmd = new SqlCommand("dbo.GetAllModulesThatHaveParams", conn))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    var p = cmd.Parameters.Add("@dbname", SqlDbType.NVarChar, 128);
                    p.Value = targetDB;
                    SqlDataReader rdr = cmd.ExecuteReader();
                    if (rdr.HasRows)
                    {
                        var parser = new TSql150Parser(true);
                        var hasEquals = false;
                        var thisParam = new string("");
                        var thisLiteral = new string("");
                        List<TSqlTokenType> whereParamsEnd   = new List<TSqlTokenType> { TSqlTokenType.Begin, TSqlTokenType.Declare, TSqlTokenType.Select, TSqlTokenType.Set, TSqlTokenType.With };
                        List<TSqlTokenType> irrelevantTokens = new List<TSqlTokenType> { TSqlTokenType.MultilineComment, TSqlTokenType.SingleLineComment, TSqlTokenType.WhiteSpace,
                                                                                         TSqlTokenType.As, TSqlTokenType.Create, TSqlTokenType.Procedure, TSqlTokenType.Function };
                        List<TSqlTokenType> assignmentTokens = new List<TSqlTokenType> { TSqlTokenType.AsciiStringLiteral, TSqlTokenType.HexLiteral, TSqlTokenType.Identifier,
                                                                                         TSqlTokenType.Integer, TSqlTokenType.Money, TSqlTokenType.Null, TSqlTokenType.Numeric,
                                                                                         TSqlTokenType.Real, TSqlTokenType.UnicodeStringLiteral };
                        while (rdr.Read())
                        {
                            hasEquals = false;
                            thisParam = string.Empty;
                            thisLiteral = string.Empty;
                            object_id  = rdr.GetInt32(0);  // Reader["object_id"]
                            definition = rdr.GetString(1); // Reader["definition"]

                            var tokens = parser.Parse(new System.IO.StringReader(definition), out IList<ParseError> errors);

                            foreach (var token in tokens.ScriptTokenStream)
                            { 
                                var tt = token.TokenType; 

                                // stop parsing when we think the parameter list has ended 
                                // for a function, we know no input parameters can appear after RETURNS, but RETURNS isn't a proper token because ¯\_(ツ)_/¯ !
                                if ( whereParamsEnd.Contains(tt) || (tt == TSqlTokenType.Identifier && token.Text.ToUpper() == "RETURNS")) 
                                {  
                                    break; 
                                }

                                if ( !irrelevantTokens.Contains(tt) ) // count(irrelevant tokens) < count(relevant tokens)
                                {
                                    if (tt == TSqlTokenType.Variable) // param name
                                    {
                                        if (thisParam != "") // if we already had a default value from the previous param, 
                                                             // we need to add a row to DataTable before we reset
                                        {
                                            paramSet.Rows.Add(object_id, thisParam, thisLiteral);
                                        }
                                        thisLiteral = string.Empty;
                                        thisParam = token.Text;
                                        hasEquals = false;
                                    }
                                    else
                                    {
                                        if (tt == TSqlTokenType.EqualsSign) // ugly way to see if there is a default assignment
                                        {
                                            hasEquals = true;
                                        }
                                        else
                                        {
                                            if (hasEquals && assignmentTokens.Contains(tt)) // is one of the valid token types that could be used as default assignment
                                            {
                                                thisLiteral = token.Text;
                                            }
                                        }
                                    }
                                }
                            }

                            if (thisParam != "") // we left the last parameter dangling
                            {
                                paramSet.Rows.Add(object_id, thisParam, thisLiteral);
                            }
                        }
                    }
                    else
                    {
                        Console.WriteLine("No relevant modules found in {0}.", targetDB);
                    }
                    rdr.Close();
                }

                if (object_id != 0)
                {
                    using (SqlCommand cmd = new SqlCommand("dbo.SaveModuleParams", conn))
                    {
                        cmd.CommandType = CommandType.StoredProcedure;
                        var p = cmd.Parameters.Add("@dbname", SqlDbType.NVarChar, 128);
                        p.Value = targetDB;
                        SqlParameter tvp = cmd.Parameters.Add("@params", SqlDbType.Structured);
                        tvp.TypeName = "dbo.ParamsWithDefaults";
                        tvp.Value = paramSet;
                        cmd.ExecuteNonQuery();
                    }
                    Console.WriteLine("Success.");
                }
            }
        }
    }
}
