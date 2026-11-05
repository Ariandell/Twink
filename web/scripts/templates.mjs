import ExcelJS from 'exceljs';
import {mkdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {toRows,sampleData,entries} from '../src/domain.js';
const dir=new URL('../../templates/',import.meta.url);
await mkdir(dir,{recursive:true});
for(const kind of ['words','idioms']){
 const book=new ExcelJS.Workbook(),sheet=book.addWorksheet(kind==='words'?'Dictionary':'Idioms');
 toRows(entries(sampleData()[kind]),kind).forEach(r=>sheet.addRow(r));
 sheet.getRow(1).font={bold:true};sheet.columns.forEach(c=>c.width=25);
 await book.xlsx.writeFile(fileURLToPath(new URL(`Twink_${kind}.xlsx`,dir)));
}
