#!/bin/bash
###############################################################################
# patch_realtime_final.sh
# - Control row now appears ABOVE carrier stats (before realtime_content)
# - Syncs with report's own groups[] campaign selector automatically
# - Removes all previous custom blocks before applying
###############################################################################
set -u
TARGET="${1:-}"
if [ -z "$TARGET" ]; then
  for p in /srv/www/htdocs/vicidial/realtime_report.php \
            /var/www/html/vicidial/realtime_report.php \
            /var/www/html/agc/realtime_report.php; do
    [ -f "$p" ] && TARGET="$p" && break
  done
fi
if [ -z "$TARGET" ] || [ ! -f "$TARGET" ]; then
  echo "ERROR: realtime_report.php not found. Pass full path."; exit 1
fi
WEBDIR=$(dirname "$TARGET")
echo ">> Target:  $TARGET"
grep -q '$PHP_SELF = preg_replace' "$TARGET" || { echo "ERROR: anchor 1 missing"; exit 2; }
grep -q 'id=realtime_content name=realtime_content' "$TARGET" || { echo "ERROR: anchor 2 missing"; exit 2; }
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="${TARGET}.bak.${STAMP}"
cp -p "$TARGET" "$BACKUP" && echo ">> Backup:  $BACKUP" || { echo "ERROR: backup failed"; exit 3; }
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
STRIPPED="$WORK/stripped.php"; PATCHED="$WORK/patched.php"

# Strip all previous CUSTOM blocks
awk '
/^###### CUSTOM: Real-Time Campaign \+ Dial Level control - AJAX handler ######/ {skip=1}
/^###### CUSTOM: Real-Time Campaign \+ Dial Level control row ######/ {skip=1}
{ if(!skip) print }
/^###### END CUSTOM AJAX handler ######/ {skip=0; next}
/^###### END CUSTOM control row ######/ {skip=0; next}
' "$TARGET" > "$STRIPPED"

python3 - "$STRIPPED" "$PATCHED" <<'PYEOF'
import sys
src = open(sys.argv[1]).read()

insert_a = "\n###### CUSTOM: Real-Time Campaign + Dial Level control - AJAX handler ######\n###### END CUSTOM AJAX handler ######\n"

insert_b = r"""
###### CUSTOM: Real-Time Campaign + Dial Level control row ######
$cdl_userB = mysqli_real_escape_string($link,$PHP_AUTH_USER);
$cdl_pB = mysqli_fetch_row(mysql_to_mysqli("SELECT modify_campaigns,user_level FROM vicidial_users WHERE user='$cdl_userB' LIMIT 1;",$link));
$cdl_canwrite_js = ($cdl_pB && $cdl_pB[0]=='1' && $cdl_pB[1] > 6) ? 'true' : 'false';
$cdl_api_url = str_replace('realtime_report.php','cdl_api.php',$PHP_SELF);
echo "<br><span id='cdl_control_row'>";
echo _QXZ("Select Campaign").": <select id='cdl_campaign'></select> &nbsp; ";
echo _QXZ("Select Dial Level").": <select id='cdl_dial_level'></select> &nbsp; ";

echo "<input type='button' id='cdl_set_btn' value='"._QXZ("Set Dial Level")."'> ";
echo "<span id='cdl_msg'></span>";
echo "</span><br>\n";
?>
<script language="Javascript">
(function(){
	var CDL_CANWRITE = <?php echo $cdl_canwrite_js; ?>;
	var CDL_API = '<?php echo $cdl_api_url; ?>';
	function cdl_id(i){return document.getElementById(i);}
	function cdl_levels(cur){
		var s=cdl_id('cdl_dial_level'); if(!s)return; s.innerHTML='';
		var vals=[]; for(var v=1;v<=12.0001;v+=0.5)vals.push(parseFloat(v.toFixed(1)));
		var c=parseFloat(parseFloat(cur).toFixed(1)); if(isNaN(c))c=1.0;
		if(vals.indexOf(c)<0){vals.push(c);vals.sort(function(a,b){return a-b;});}
		for(var i=0;i<vals.length;i++){
			var o=document.createElement('option'); o.value=vals[i].toFixed(1); o.text=vals[i].toFixed(1);
			if(vals[i]===c)o.selected=true; s.appendChild(o);
		}
	}
	function cdl_call(params,cb){
		var u=(typeof user!=='undefined'&&user)?user:'';
		var x=new XMLHttpRequest();
		x.open('GET',CDL_API+'?'+params+'&cdl_u='+encodeURIComponent(u),true);
		x.onreadystatechange=function(){
			if(x.readyState==4){
				if(x.status==200){var r={}; try{r=JSON.parse(x.responseText);}catch(e){r={ok:false,err:'parse:'+x.responseText.substring(0,80)};} cb(r);}
				else cb({ok:false,err:'http_'+x.status});
			}
		};
		x.send();
	}
	function cdl_msg(t){var m=cdl_id('cdl_msg'); if(!m)return; m.innerHTML=' '+t; setTimeout(function(){if(m)m.innerHTML='';},3000);}
	function cdl_loadlevel(){
		var c=cdl_id('cdl_campaign'); if(!c||!c.value)return;
		cdl_call('cdl_action=get&cdl_campaign='+encodeURIComponent(c.value),function(r){
			if(r.ok)cdl_levels(r.dial_level); else cdl_msg('level err:'+r.err);
		});
	}
	function cdl_loadcampaigns(preselectID){
		cdl_call('cdl_action=campaigns&cdl_campaign=NA',function(r){
			var sel=cdl_id('cdl_campaign'); if(!sel)return;
			if(r.ok&&r.campaigns&&r.campaigns.length){
				CDL_CANWRITE=!!r.can_write; sel.innerHTML='';
				for(var i=0;i<r.campaigns.length;i++){
					var c=r.campaigns[i],o=document.createElement('option');
					o.value=c.campaign_id; o.text=c.campaign_name+' ('+c.campaign_id+')'; sel.appendChild(o);
				}
				if(preselectID && preselectID!='ALL-ACTIVE'){sel.value=preselectID;}
				cdl_loadlevel();
			} else {
				sel.innerHTML='<option value="">'+(r.err?'err:'+r.err:'(no campaigns)')+'</option>';
			}
		});
	}
	window.cdl_sync_from_report = function(){
		var grp=document.getElementById('groups[]');
		if(!grp) return;
		var picked=[],isAll=false;
		for(var i=0;i<grp.options.length;i++){
			if(grp.options[i].selected){
				if(grp.options[i].value==='ALL-ACTIVE'){isAll=true;break;}
				picked.push(grp.options[i].value);
			}
		}
		if(!isAll && picked.length===1){
			var sel=cdl_id('cdl_campaign'); if(!sel)return;
			sel.value=picked[0];
			if(sel.value!==picked[0]){cdl_loadcampaigns(picked[0]);}
			else{cdl_loadlevel();}
		}
	};
	var cs=cdl_id('cdl_campaign'); if(cs)cs.onchange=cdl_loadlevel;
	var sb=cdl_id('cdl_set_btn'); if(sb)sb.onclick=function(){
		var c=cdl_id('cdl_campaign'),d=cdl_id('cdl_dial_level');
		if(!c||!c.value){cdl_msg('Pick a campaign first');return;}
		if(!CDL_CANWRITE){cdl_msg('No permission');return;}
		cdl_call('cdl_action=set&cdl_campaign='+encodeURIComponent(c.value)+'&cdl_dial_level='+encodeURIComponent(d.value),function(r){
			if(r.ok){cdl_levels(r.dial_level);cdl_msg('Dial level set to '+r.dial_level);}
			else cdl_msg('Error: '+r.err);
		});
	};

	window.addEventListener('load',function(){
		var grp=document.getElementById('groups[]');
		if(grp){grp.addEventListener('change',function(){window.cdl_sync_from_report();});}
	});
	cdl_levels('1.0');
	cdl_loadcampaigns();
})();
</script>
<?php
###### END CUSTOM control row ######
"""

lines = src.split('\n'); out = []; doneA = doneB = False
for line in lines:
    if not doneA and '$PHP_SELF = preg_replace' in line:
        out.append(line); out.extend(insert_a.split('\n')); doneA=True; continue
    if not doneB and 'id=realtime_content name=realtime_content' in line:
        out.extend(insert_b.split('\n')); doneB=True; out.append(line); continue
    out.append(line)

if not doneA or not doneB:
    print("ERROR: anchor not found doneA=%s doneB=%s" % (doneA,doneB), file=sys.stderr); sys.exit(9)

result = '\n'.join(out)
old = "groupQS = temp_camp_choices;"
new = "groupQS = temp_camp_choices;\n\t\tif (typeof window.cdl_sync_from_report === 'function') { window.cdl_sync_from_report(); }"
if old in result:
    result = result.replace(old, new, 1); print("groupQS sync hook: applied")
else:
    print("WARNING: groupQS hook not found - sync on SUBMIT may not work")

open(sys.argv[2], 'w').write(result)
print("Injection OK, lines: %d" % len(result.split('\n')))
PYEOF

if [ $? -ne 0 ]; then
  echo "ERROR: injection failed. File unchanged (backup at $BACKUP)."; exit 4
fi

if command -v php >/dev/null 2>&1; then
  php -l "$PATCHED" >/dev/null 2>&1 || { echo "ERROR: PHP syntax check failed."; php -l "$PATCHED"; exit 5; }
  echo ">> PHP syntax: OK"
else echo ">> NOTE: php CLI not found."; fi

cat "$PATCHED" > "$TARGET"
echo ""
echo ">> DONE. realtime_report.php updated."
echo ">> Restore: cp -p '$BACKUP' '$TARGET'"
echo ">> No changes needed to cdl_api.php."
