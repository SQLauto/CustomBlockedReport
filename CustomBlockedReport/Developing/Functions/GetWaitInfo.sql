
IF EXISTS
(
    SELECT *
    FROM sys.objects
    WHERE object_id = OBJECT_ID(N'[Bpr].[GetWaitInfo]')
          AND type IN(N'FN', N'IF', N'TF', N'FS', N'FT')
)
    DROP FUNCTION [Bpr].[GetWaitInfo];
GO
CREATE FUNCTION [Bpr].[GetWaitInfo]
(@blockingSessionId INT,
 @blockedSessionId  INT,
 @blockingEcid      INT = 0,
 @blockedEcid       INT = 0
)
RETURNS @waitInfo TABLE
([Level]                        [INT] NULL,
 [DataBaseName]                 [NVARCHAR](128) NULL,
 [VictemProgramName]            [NVARCHAR](128) NULL,
 [VictemHostName]               [NVARCHAR](128) NULL,
 [VictemSessionId]              [SMALLINT] NULL,
 [VictemSessionEcid]            [INT] NULL,
 [VictemDruationSec]            [BIGINT] NULL,
 [VictemWaitType]               [NVARCHAR](60) NULL,
 [VictemDescription]            [NVARCHAR](3072) NULL,
 [VictemWaitResource]           [NVARCHAR](256) NOT NULL,
 [VictemStartTime]              [DATETIME] NOT NULL,
 [Command]                      [NVARCHAR](32) NOT NULL,
 [CommandText]                  [NVARCHAR](MAX) NULL,
 [QueryPlan]                    [XML] NULL,
 [VictemStatus]                 [NVARCHAR](30) NOT NULL,
 [VictemIsolationLevel]         [SMALLINT] NOT NULL,
 [BLOCKED_BY]                   [VARCHAR](13) NOT NULL,
 [BlockingSessionId]            [SMALLINT] NULL,
 [BlockingEcid]                 [INT] NULL,
 [BlockingProgramName]          [NVARCHAR](128) NULL,
 [BlockingHostName]             [NVARCHAR](128) NULL,
 [BlockingLastRequestStartTime] [DATETIME] NOT NULL,
 [BlockingLastCommandText]      [NVARCHAR](MAX) NULL,
 [BlockingStatus]               [NVARCHAR](30) NOT NULL,
 [BlockingIsolationLevel]       [SMALLINT] NOT NULL
)
WITH EXECUTE AS OWNER
AS
     BEGIN
         WITH Blocking(BlockedId,
                       Ecid,
                       BlockingId,
                       BlockingEcid,
                       LevelId)
              AS (
	--Anchor 

              SELECT session_id,
                     ISNULL(exec_context_id, 0) exec_context_id,
                     blocking_session_id,
                     ISNULL(blocking_exec_context_id, 0) blocking_exec_context_id,
                     0 Level
              FROM sys.dm_os_waiting_tasks
              WHERE blocking_session_id IS NOT NULL
                    AND blocking_session_id = @blockingSessionId
                    AND session_id = @blockedSessionId
                    AND ISNULL(exec_context_id, 0) = @blockedEcid
                    AND ISNULL(blocking_exec_context_id, 0) = @blockingEcid
              UNION ALL
	--Recursive

              SELECT session_id,
                     ISNULL(exec_context_id, 0) exec_context_id,
                     blocking_session_id,
                     ISNULL(blocking_exec_context_id, 0) blocking_exec_context_id,
                     LevelId + 1 LevelId
              FROM sys.dm_os_waiting_tasks r
                   INNER JOIN blocking b ON r.session_id = b.BlockingId
                                            AND r.exec_context_id = b.BlockingEcid)
              INSERT INTO @waitInfo
              ([Level],
               [DataBaseName],
               [VictemProgramName],
               [VictemHostName],
               [VictemSessionId],
               [VictemSessionEcid],
               [VictemDruationSec],
               [VictemWaitType],
               [VictemDescription],
               [VictemWaitResource],
               [VictemStartTime],
               [Command],
               [CommandText],
               [QueryPlan],
               [VictemStatus],
               [VictemIsolationLevel],
               [BLOCKED_BY],
               [BlockingSessionId],
               [BlockingEcid],
               [BlockingProgramName],
               [BlockingHostName],
               [BlockingLastRequestStartTime],
               [BlockingLastCommandText],
               [BlockingStatus],
               [BlockingIsolationLevel]
              )
                     SELECT bl.levelid Level,
                            DB_NAME(er.database_id) DataBaseName,
                            es.program_name VictemProgramName,
                            es.host_name VictemHostName,
                            bl.BlockedId VictemSessionId,
                            bl.Ecid VictemSessionEcid,
                            wt.wait_duration_ms / 1000 VictemDruationSec,
                            wt.wait_type VictemWaitType,
                            wt.resource_description VictemDescription,
                            er.wait_resource VictemWaitResource,
                            es.last_request_start_time VictemStartTime,
                            er.command Command,
                            est.text CommandText,
                            eqp.query_plan QueryPlan,
                            es.status VictemStatus,
                            es.transaction_isolation_level VictemIsolationLevel,
                            'BLOCKED BY-->' AS BLOCKED_BY,
                            bl.BlockIngId BlockingSessionId,
                            bl.BlockingEcid BlockingEcid,
                            esBlocking.program_name BlockingProgramName,
                            esBlocking.host_name BlockingHostName,
                            esBlocking.last_request_start_time BlockingLastRequestStartTime,
                            estBlocking.text BlockingLastCommandText,
                            esBlocking.status BlockingStatus,
                            esBlocking.transaction_isolation_level BlockingIsolationLevel
	--,DTL.[resource_type] AS [resource type]
	--,CASE
	--	WHEN DTL.[resource_type] IN ('DATABASE', 'FILE', 'METADATA') THEN DTL.[resource_type]
	--	WHEN DTL.[resource_type] = 'OBJECT' THEN OBJECT_NAME(DTL.resource_associated_entity_id)
	--	WHEN DTL.[resource_type] IN ('KEY', 'PAGE', 'RID') THEN (SELECT
	--				( CASE WHEN s.name IS NOT NULL THEN s.name  +'.' ELSE '' END ) + OBJECT_NAME(p.[object_id])
	--			FROM sys.partitions p
	--			INNER JOIN sys.objects o on o.object_id = p.object_id
	--			INNER JOIN sys.schemas s on o.schema_id = s.schema_id
	--			WHERE p.[hobt_id] = DTL.[resource_associated_entity_id])
	--	ELSE 'Unidentified'
	--END AS [Parent Object]
	--,DTL.[request_mode] AS [Lock Type]
	--,DTL.[request_status] AS [Request Status]
                     FROM blocking bl WITH (NOLOCK)
                          LEFT OUTER JOIN sys.dm_os_waiting_tasks wt WITH (NOLOCK) ON bl.BlockedId = wt.session_id
                                                                                      AND bl.Ecid = wt.exec_context_id
--INNER JOIN sys.dm_tran_locks DTL
--	ON DTL.lock_owner_address = WT.resource_address
                          LEFT OUTER JOIN sys.dm_exec_sessions es WITH (NOLOCK) ON bl.BlockedId = es.session_id
                          LEFT OUTER JOIN sys.dm_exec_sessions esBlocking WITH (NOLOCK) ON bl.BlockingId = esBlocking.session_id
                          LEFT OUTER JOIN sys.dm_exec_requests er WITH (NOLOCK) ON es.session_id = er.session_id
                          LEFT OUTER JOIN sys.dm_exec_connections ec WITH (NOLOCK) ON bl.BlockIngId = ec.session_id
                          OUTER APPLY sys.dm_exec_sql_text(er.sql_handle) est
                          OUTER APPLY sys.dm_exec_sql_text(ec.most_recent_sql_handle) estBlocking
                          OUTER APPLY sys.dm_exec_query_plan(er.plan_handle) eqp
                     WHERE es.is_user_process = 1;
         RETURN;
     END;
GO
ADD SIGNATURE TO OBJECT::[Bpr].[GetWaitInfo] BY CERTIFICATE [PBR] WITH PASSWORD = '$tr0ngp@$$w0rd';
GO 
